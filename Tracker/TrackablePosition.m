classdef TrackablePosition < Trackable
    %TRACKABLEPOSITION Makes sure that the experiment is still focused on
    %the desired NV center 
    % The class uses a simple algorithm to counter mechanical drift
    % of the stage
    
    % Maybe inherit from StageScanner???
    properties (SetAccess = private)
        stepNum = 0;	% int. Steps since beginning of tracking
        currAxis = 1;   % int. Numerical value of currently scanned axis (1 for X, etc.)

        mSignal
        mScanParams     % Object of class StageScanParams, to store current running scan
        stepSize        % 3x1 double. Holds the current size of position step
        
        mStageName
        mLaserName
    end
    
    properties (Constant)
        THRESHOLD_FRACTION = 0.02;  % Change is significant if dx/x > threshold fraction
        NUM_MAX_ITERATIONS = 100;   % After that many steps, convergence is improbable
        DETECTION_DURATION = 0.1 ;  % in seconds
        
        % vector constants, for [X Y Z]
        INITIAL_STEP_VECTOR = [0.1 0.1 0.2];    %[0.1 0.1 0.05];
        MINIMUM_STEP_VECTOR = [0.02 0.02 0.05]; %[0.01 0.01 0.01];
        STEP_RATIO_VECTOR = 0.5*ones(1, 3);
        ZERO_VECTOR = [0 0 0];
        
        HISTORY_FIELDS = {'position', 'step', 'time', 'value'}
        
        DEFAULT_CONTINUOUS_TRACKING = false;
    end
    
    methods
        function obj = TrackablePosition(stageName,laserName)
            expName = Tracker.TRACKABLE_POSITION_NAME;
            obj@Trackable(expName);
            obj.mStageName = stageName;
            obj.mLaserName = laserName;
            
            obj.mScanParams = StageScanParams;
        end

        function start(obj)
            %%%% initialize %%%%
            obj.resetAlgorithm;
            obj.isCurrentlyTracking = true;
            stage = getObjByName(obj.mStageName);
            spcm = getObjByName(Spcm.NAME);
            spcm.setSPCMEnable(true);
            % todo: if laser is off, turn it on
            
            %%%% Get initial position and signal value, for history %%%%
            % Set parameters for scan
            axes = stage.getAxis(stage.availableAxes);
            sp = obj.mScanParams;
            sp.fixedPos = stage.Pos(axes);
            sp.isFixed = true(size(sp.isFixed));    % all axes are fixed on initalization
            scanner = StageScanner.init;
            if ~ischar(scanner.mStageName) || ~strcmp(scanner.mStageName,obj.mStageName)
                scanner.switchTo(obj.mStageName)
                EventStation.anonymousWarning('Changing scanning stage!')
            end
            
%             obj.mSignal = scanner.scanPoint(stage, spcm, sp);
            obj.mSignal = scanner.dummyScanGaussian(sp);          % todo: remove when definitely works
            obj.recordCurrentState;     % record starting point (time == 0)

            % Execution of at least one iteration is acheived by using
            % {while(true) {statements} if(condition) {break}}
            while true
                obj.HovavAlgorithm;
                obj.recordCurrentState;
                if ~obj.isRunningContinuously; break; end
                obj.sendEventTrackableExpEnded;
            end
            
            obj.isCurrentlyTracking = false;
            obj.sendEventTrackableExpEnded;     % We want the GUI to catch that the tracker is not tracking anymore
        end
                
        function stop(obj)
            obj.stopFlag = true;
            obj.isCurrentlyTracking = false;
            obj.sendEventTrackableExpEnded;
        end
        
        function reset(obj)
            obj.resetAlgorithm;
            obj.timer = [];
            obj.clearHistory;
        end
        
        function params = getAllTrackalbeParameter(obj) %#ok<MANU>
        % Returns a cell of values/paramters from the trackable experiment
        params = NaN;
        end
        
        function str = textOutput(obj)
            if all(obj.stepSize <= obj.MINIMUM_STEP_VECTOR)
                str = sprintf('Local maximum was found in %u steps', obj.stepNum);
            elseif obj.stopFlag
                str = 'Operation terminated by user';
            elseif obj.isDivergent
                str = 'Maximum number of iterations reached without convergence';
            else
                str = 'This shouldn''t have happenned...';
            end
        end
    end
        
    methods (Access = private)
        function intialize(obj)
            obj.reset;
%             stage = getObjByName(obj.stageName);    
        end
        
        function bool = isDivergent(obj)
            % If we arrive at the maximum number of iterations, we assume
            % the tracking sequence will not converge, and we stop it
            bool = (obj.stepNum >= obj.NUM_MAX_ITERATIONS);
        end
        
        function recordCurrentState(obj)
            record = struct;
            record.position = obj.mScanParams.fixedPos;
            record.step = obj.stepSize;
            record.value = obj.mSignal;
            record.time = obj.myToc;  % personalized toc function
            
            obj.mHistory{end+1} = record;
            obj.sendEventTrackableUpdated;
        end
        
        function resetAlgorithm(obj)
            obj.stopFlag = false;
            obj.stepNum = 0;
            obj.currAxis = 1;
            
            obj.mSignal = [];
            obj.mScanParams = StageScanParams;
            obj.stepSize = obj.INITIAL_STEP_VECTOR;
        end
    end
    
    methods (Static)
        function bool = isDifferenceAboveThreshhold(x0, x1)
            bool = (x0-x1) > TrackablePosition.THRESHOLD_FRACTION;
        end
    end

    %% Scanning algoithms.
    % For now, only one, should include more in the future
    methods
        function HovavAlgorithm(obj)
            % Moves axis-wise (cyclicly) to the direction of the
            % derivative. In other words, this is a simple axis-wise form
            % of gradient ascent.
            stage = getObjByName(obj.mStageName);
            axes = stage.getAxis(stage.availableAxes);
            scanner = StageScanner.init;
            % Initialize scan parameters for scanning
            sp = obj.mScanParams;
            sp.fixedPos = stage.Pos(axes);
            sp.numPoints = 3 * ones(1,length(axes));
            sp.isFixed = true(size(sp.isFixed));    % all axes are fixed on initalization
            sp.fastScan = stage.hasFastScan;        % scan fast, if possible
            
            while ~obj.stopFlag && any(obj.stepSize > obj.MINIMUM_STEP_VECTOR) && ~obj.isDivergent
                if obj.stepSize(obj.currAxis) > obj.MINIMUM_STEP_VECTOR(obj.currAxis)
                    obj.stepNum = obj.stepNum + 1;
                    pos = sp.fixedPos(obj.currAxis);
                    step = obj.stepSize(obj.currAxis);
                    
                    % scan to find forward and backward 'derivative'
                    sp.isFixed(obj.currAxis) = false;
                    sp.from(obj.currAxis) = pos - step;
                    sp.to(obj.currAxis) = pos + step;
                    
%                     signals = scanner.scan(stage, spcm, sp);    % scans [p-dp, p, p+dp]
                    signals = scanner.dummyScanGaussian(sp);
                    % todo: remove when definitely works
                    shouldMoveBack = obj.isDifferenceAboveThreshhold(signals(1), signals(2));
                    shouldMoveFwd = obj.isDifferenceAboveThreshhold(signals(3), signals(2));
                    
                    shouldContinue = false;
                    if shouldMoveBack
                        if shouldMoveFwd
                            % local minimum; don't move
                            disp('Conflict.... make longer scans?')
                        else
                            % should go back and look for maximum:
                            % prepare for next step
                            newStep = -step;
                            pos = pos + newStep;
                            newSignal = signals(1);   % value @ best position yet
                            shouldContinue = true;
                        end
                        
                    else
                        if shouldMoveFwd
                            % should go forward and look for maximum:
                            % prepare for next step
                            newStep = step;
                            pos = pos + newStep;
                            newSignal = signals(3);   % value @ best position yet
                            shouldContinue = true;
                        else
                            % local maximum or plateau; don't move
                        end
                    end
                    
                    while shouldContinue && ~obj.isDivergent && ~obj.stopFlag
                        % we are still iterating; save current position before moving on
                        obj.mSignal = newSignal;    % Save value @ best position yet
                        obj.recordCurrentState;
                        
                        obj.stepNum = obj.stepNum + 1;
                        % New pos = (pos + step), if you should move forward;
                        %           (pos - step), if you should move backwards
                        pos = pos + newStep;
                        sp.fixedPos(obj.currAxis) = pos;
                        sp.isFixed(obj.currAxis) = true;
%                         newSignal = scanner.scanPoint(stage, spcm, sp);
                        newSignal = scanner.dummyScanGaussian(sp);
%                         % todo: remove when definitely works
                        
                        shouldContinue = obj.isDifferenceAboveThreshhold(newSignal, obj.mSignal);
                    end
                    obj.stepSize(obj.currAxis) = step/2;
                end
                sp.isFixed(obj.currAxis) = true;    % We are done with this axis, for now
                obj.currAxis = mod(obj.currAxis,3) + 1; % Cycle through [1 2 3]
            end
        end
    end
    
end
