classdef SpcmCounter < Experiment
    %SPCMCOUNTER Read counts from SPCM via timer
    %   When switched on (reset), inits the vector of reads to be empty,
    %   and start a timer to read every 100ms.
    %   every time the timer clocks, a new read will be added to the
    %   vector.
    %
    %   The counter implements events from class Experiment, and adds event
    %   EVENT_SPCM_COUNTER_RESET, when we want to clear all results until
    %   now, and start anew.
    
    properties
        records     % vector, saves all previous scans since reset
        integrationTimeMillisec     % float, in milliseconds
    end
    
    properties (Access = private)
        mTimer	% Timer for new records
    end
    
    properties (Constant)
        NAME = 'SpcmCounter'

        EVENT_SPCM_COUNTER_RESET = 'SpcmCounterReset';
        
        INTEGRATION_TIME_DEFAULT_MILLISEC = 100;
        DEFAULT_EMPTY_STRUCT = struct('time', 0, 'kcps', NaN, 'std', NaN);
    end
    
    methods
        function obj = SpcmCounter
            obj@Experiment(SpcmCounter.NAME);
            obj.integrationTimeMillisec = obj.INTEGRATION_TIME_DEFAULT_MILLISEC;
            obj.records = obj.DEFAULT_EMPTY_STRUCT;
            obj.mTimer = ExactTimer;
            obj.stopFlag = true; % It is stopped (not running) by default
            
            obj.averages = 1;   % This Experiment has no averaging over repeats
            obj.shouldAutosave = false;
        end
    end
    
    methods (Access = protected)
        function sendEventReset(obj)
            obj.sendEvent(struct(obj.EVENT_SPCM_COUNTER_RESET,true));
        end
        
        function reset(obj)
            obj.records = obj.DEFAULT_EMPTY_STRUCT;
            obj.mTimer.reset;
            obj.sendEventReset;
        end
        
        function newRecord(obj, kcps, std)
            % creates new record in a struct of the type "record" =
            % record.{time,kcps,std}, with proper validation.
            time = obj.mTimer.toc;  % Personalized timer
            
            if kcps < 0 || std < 0 || kcps < std
                recordNum = length(obj.records);
                EventStation.anonymousWarning('Invalid values in time %d (record #%i)', time, recordNum)
            end
            obj.records(end + 1) = struct('time', time, 'kcps', kcps, 'std', std);
        end
    end
       
    methods % Setters and getters
        function [time, kcps, std] = getRecords(obj, lenOpt)
            lenRecords = length(obj.records);
            if ~exist('lenOpt', 'var')
                wrapLength = lenRecords;
            else
                wrapLength = lenOpt;
            end
            
            difference = lenRecords - wrapLength;
            if difference < 0
                padding = abs(difference) - 1;
                maxTime = wrapLength*obj.integrationTimeMillisec/1000;  % Create time for end of wrap
                zeroStruct = struct('time', maxTime, 'kcps', 0, 'std', 0);
                data = [obj.records, ...
                    repelem(obj.DEFAULT_EMPTY_STRUCT, padding), ...
                    zeroStruct];
            elseif difference == 0
                data = obj.records;
            else
                position = difference + 1;
                data = obj.records(position:end);
            end
            
            time = [data.time];
            kcps = [data.kcps];
            std = [data.std];
        end
        
        function set.integrationTimeMillisec(obj, newValue)
            if ValidationHelper.isValuePositiveInteger(newValue)
                obj.integrationTimeMillisec = newValue;
            else
                EventStation.anonymousWarning('Integration time needs to be a positive integer. Reverting.')
            end
        end
    end
    
    %% Overridden from Experiment
    methods
        function run(obj)
            obj.stopFlag = false;
            sendEventExpResumed(obj);
            
            integrationTime = obj.integrationTimeMillisec;  % For convenience
            
            spcm = getObjByName(Spcm.NAME);
            if isempty(spcm); throwBaseObjException(Spcm.NAME); end
            spcm.setSPCMEnable(true);
            spcm.prepareReadByTime(integrationTime/1000);
            
            % Prepare for parallel pool
            if isempty(gcp('nocreate'))
                paralPool = parpool(1);
            else
                paralPool = gcp();
            end
            countingObj = spcm.variablesForTimeRead;
            
            try
                % Creating data to be saved, using workers
                f = parfeval(paralPool, @spcm.readFromTime, 2, countingObj);
                while ~obj.stopFlag
                    if strcmp(f.State, 'finished')
                        [kcps, std] = fetchOutputs(f);
                        obj.newRecord(kcps, std);
                        obj.sendEventDataUpdated;
                        
                        % Start a new job
                        f = parfeval(paralPool, @spcm.readFromTime, 2, countingObj);
                    end
                    
                    % Update integration time, if necessary
                    if integrationTime ~= obj.integrationTimeMillisec
                        integrationTime = obj.integrationTimeMillisec;
                        spcm.clearTimeRead;
                        spcm.prepareReadByTime(integrationTime/1000);
                    end
                end
                spcm.clearTimeTask;
                
            catch err
                obj.pause;
                try
                    spcm.clearTimeTask;
                catch
                end
                rethrow(err);
            end
        end
        
        function pause(obj)
            obj.stopFlag = true;
            pause((obj.integrationTimeMillisec + 1) / 1000);    % Let me finish what I was doing
            obj.sendEventExpPaused;
        end
        
        function resetHistory(obj)
            obj.reset;
        end
    end
        
    methods (Access = protected)
        % Functions that are abstract in superclass. Not relevant here.
        function prepare(obj) %#ok<MANU>
        end
        function perform(obj) %#ok<MANU> 
        end
        function alternateSignal(obj)%#ok<MANU>
        end
        function wrapUp(obj) %#ok<MANU>
        end
    end
    
    %%
	methods (Static)
        function init
            obj = getObjByName(SpcmCounter.NAME);
            if isempty(obj)
                % There was no such object, so we create one
                SpcmCounter;
            else
                obj.pause;
            end
        end
    end

end