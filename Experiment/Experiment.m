classdef Experiment < EventSender & EventListener & Savable
    %EXPERIMENT Summary of this class goes here
    %   Detailed explanation goes here
    
    properties (SetAccess = protected)
        mCategory               % string. For loading (might change in subclasses)
       
        changeFlag = true;      % logical. True if changes have been made 
                                % in Experiment parameters, but not yet
                                % uploaded to hardware
        
        mCurrentXAxisParam      % ExpParameter in charge of axis x (which has name and value)
        mCurrentYAxisParam		% ExpParameter in charge of axis y (which has name and value)
    end
    
    properties
        isOn = false;       % Maybe isOn is like ~(the private property stopFlag)?
        
        averages            % int. Number of measurements to average from
        repeats             % int. Number of repeats per measurement
        track               % logical. initialize tracking
        trackThreshhold     % double (between 0 and 1). Change in signal that will start the tracker
        laserInitializationDuration  % laser initialization in pulsed experiments
        laserOnDelay        %in \mus
        laserOffDelay       %in \mus
        mwOnDelay           %in \mus
        mwOffDelay          %in \mus
        detectionDuration   % detection windows, in \mus
        
        greenLaserPower     % in V
    end
    
    properties (Access = private)
        stopFlag = 0;
        pauseFlag = 0;	% 0 -> new signal will be acquired. 1 --> signal will be required.
        pausedAverage = 0; 
    end
    
    properties (Abstract, Constant, Hidden)
        EXP_NAME        % char array. Name of experiment, as recognized by the system.
    end
    
    properties (Constant)
        NAME = 'Experiment'
        
        PATH_ALL_EXPERIMENTS = sprintf('%sControl code\\%s\\Experiment\\Experiments\\', ...
            PathHelper.getPathToNvLab(), PathHelper.SetupMode);
        
        EVENT_DATA_UPDATED = 'dataUpdated'      % when something changed regarding the plot (new data, change in x\y axis, change in x\y labels)
        EVENT_EXP_RESUMED = 'experimentResumed' % when the experiment is starting to run
        EVENT_EXP_PAUSED = 'experimentPaused'   % when the experiment stops from running
        EVENT_PLOT_ANALYZE_FIT = 'plot_analyzie_fit'        % when the experiment wants the plot to draw the fitting-function-analysis
        EVENT_PARAM_CHANGED = 'experimentParameterChanged'  % when one of the sequence params \ general params is changed
        
        % Exception handling
        EXCEPTION_ID_NO_EXPERIMENT = 'getExp:noExp';
        EXCEPTION_ID_NOT_CURRENT = 'getExp:notCurrExp';
    end
    
    methods
        function sendEventDataUpdated(obj); obj.sendEvent(struct(obj.EVENT_DATA_UPDATED, true)); end
        function sendEventExpResumed(obj); obj.sendEvent(struct(obj.EVENT_EXP_RESUMED, true)); end
        function sendEventExpPaused(obj); obj.sendEvent(struct(obj.EVENT_EXP_PAUSED, true)); end
        function sendEventPlotAnalyzeFit(obj); obj.sendEvent(struct(obj.EVENT_PLOT_ANALYZE_FIT, true)); end
        function sendEventParamChanged(obj); obj.sendEvent(struct(obj.EVENT_PARAM_CHANGED, true)); end
        
        function obj = Experiment()
            obj@EventSender(Experiment.NAME);
            obj@Savable(Experiment.NAME);
            obj@EventListener({Tracker.NAME, StageScanner.NAME});
            
            obj.mCurrentXAxisParam = ExpParamDoubleVector('X axis', [], obj.EXP_NAME);
            obj.mCurrentYAxisParam = ExpParamDoubleVector('Y axis', [], obj.EXP_NAME);
            
            obj.mCategory = Savable.CATEGORY_EXPERIMENTS; % will be overridden in Trackable
            
            % Copy parameters from previous experiment (if exists) and replace its base object
            try
                prevExp = getObjByName(Experiment.NAME);
                if isa(prevExp, 'Experiment') && isvalid(prevExp)
                    prevExp.pause;
                    obj.robExperiment(prevExp);
                end % No need to tell the user otherwise.
                delete(prevExp);
                replaceBaseObject(obj);
            catch
                % We got here if there was no Experiment here yet
                addBaseObject(obj);
            end
        end
        
        function cellOfStrings = getAllExpParameterProperties(obj)
            % Get all the property-names of properties from the
            % Experiment object that are from type "ExpParameter"
            allVariableProperties = obj.getAllNonConstProperties();
            isPropExpParam = cellfun(@(x) isa(obj.(x), 'ExpParameter'), allVariableProperties);
            cellOfStrings = allVariableProperties(isPropExpParam);
        end
        
        function robExperiment(obj, prevExperiment)
            % Get all the ExpParameter's from the previous experiment
            % prevExperiment = the previous experiment
            
            for paramNameCell = prevExperiment.getAllExpParameterProperties()
                paramName = paramNameCell{:};
                if isprop(obj, paramName)
                    % if the current experiment has this property also
                    obj.(paramName) = prevExperiment.(paramName);
                    obj.(paramName).expName = obj.EXP_NAME;  % expParam, I am (now) your parent!
                end
            end
        end
        
    end
    
    %% Running
    methods
        function run(obj)
            prepare(obj)
            
            obj.stopFlag = false;
            sendEventExpResumed(obj);
            for i = 1:obj.averages
                perform(obj);
                sendEventDataUpdated(obj)
            end
            
            obj.stopFlag = true;
            sendEventExpPaused(obj);
        end
        
        function pause(obj)
            obj.stopFlag = true;
            sendEventExpPaused(obj);
        end
    end
    
    %% To be overridden
    methods (Abstract)
        % Specifics of each of the experiments
        prepare(obj) 
        
        perform(obj)
        
        analyze(obj)
    end
    
    
    %% Overridden from EventListener
    methods
        % When events happen, this function jumps.
        % Event is the event sent from the EventSender
        function onEvent(obj, event)
            if isfield(event.extraInfo, Tracker.EVENT_TRACKER_FINISHED)
                % todo - stuff
            elseif isfield(event.extraInfo, StageScanner.EVENT_SCAN_STARTED)
                obj.pause;
            end
        end
    end
    
    
    %% Overridden from Savable
    methods (Access = protected)
        function outStruct = saveStateAsStruct(obj, category, type) %#ok<INUSD>
            % Saves the state as struct. if you want to save stuff, make
            % (outStruct = struct;) and put stuff inside. If you dont
            % want to save, make (outStruct = NaN;)
            %
            % category - string. Some objects saves themself only with
            %                    specific category (image/experimetns/etc)
            % type - string.     Whether the objects saves at the beginning
            %                    of the run (parameter) or at its end (result)
            
            outStruct = NaN;
            
            % mCategory is overrided by Tracker, and we need to check it
            if ~strcmp(category,obj.mCategory); return; end
            
        end
        
        function loadStateFromStruct(obj, savedStruct, category, subCategory) %#ok<INUSD>
            % loads the state from a struct.
            % to support older versoins, always check for a value in the
            % struct before using it. view example in the first line.
            % category - a string, some savable objects will load stuff
            %            only for the 'image_lasers' category and not for
            %            'image_stages' category, for example
            % subCategory - string. could be empty string
            
            if isfield(savedStruct, 'some_value')
                obj.my_value = savedStruct.some_value;
            end
        end
        
        function string = returnReadableString(obj, savedStruct) %#ok<INUSD>
            % return a readable string to be shown. if this object
            % doesn't need a readable string, make (string = NaN;) or
            % (string = '');
            
            string = NaN;
        end
    end
    
    %% Helper functions
    methods (Static)
        function obj = init
            % Creates a default Experiment.
            try
                % Logic is reversed (without a clean way out):
                % if the try block succeeds, then we need to output a
                % warning.
                getObjByName(Experiment.NAME);
                EventStation.anonymousWarning('Deleting Previous experiment')
            catch
            end
            obj = ExperimentDefault;
        end
        
        function tf = current(newExpName)
            % logical. Whether the requested name is the current one (i.e.
            % obj.EXP_NAME).
            %
            % see also: GETEXPBYNAME
            try
                exp = getObjByName(Experiment.NAME);
                tf = strcmp(exp.EXP_NAME, newExpName);
            catch
                tf = false;
                EventStation.anonymousWarning('I don''t know the Experiment you asked for!');
            end
        end

        function namesCell = getExperimentNames()
            %GETEXPERIMENTSNAMES returns cell of char arrays with names of
            %valid Experiments.
            % Algorithm: scan '\Experiments' folder, and get the Constant
            % property 'EXP_NAME' from each file (if exists). Add also
            % 'SpcmCounter', whatever be in the folder
            
            
            % Get 'regular' Experiments
            path = Experiment.PATH_ALL_EXPERIMENTS;
            [~, expFileNames] = PathHelper.getAllFilesInFolder(path);
            % Get Trackables
            path2 = Trackable.PATH_ALL_TRACKABLES;
            [~, trckblFileNames] = PathHelper.getAllFilesInFolder(path2);
            % Join
            expFileNames = [expFileNames, trckblFileNames];
            
            % Extract names
            namesCell = cell(size(expFileNames));
            for i = 1:length(expFileNames)
                expClassName = PathHelper.removeDotSuffix(expFileNames{i});
                eval(['temp = ',expClassName,'.EXP_NAME;'])
                namesCell{i} = temp;
            end
            namesCell{end+1} = SpcmCounter.EXP_NAME;
            
        end
    end
    
end