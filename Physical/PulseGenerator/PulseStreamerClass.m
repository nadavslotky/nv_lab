classdef (Sealed) PulseStreamerClass < handle
    properties (Dependent = true)
        channelNames
        channelValues
        duration %mus
        time
        nickname
        sequence
        repeats
    end
    
    properties (Constant = true) 
        maxDigitalChannels = 8;
        minDuration = 0; %mus
        maxDuration = Inf; %mus
        maxPulses = 10e6;
        maxRepeats = Inf;
    end
    
    properties (Access = private)
        ps % Local PS type
        channelNamesPrivate
        channelValuesPrivate
        durationPrivate %mus
        nicknamePrivate
        sequencePrivate
        repeatsPrivate
    end
    
    methods (Static, Access = public) % Get instance constructor
        function obj = GetInstance()
            % Returns a singelton instance.
            persistent localObj
            if isempty(localObj) || ~isvalid(localObj)
                localObj = PulseStreamerClass();
                localObj.Initialize;
            end
            obj = localObj;
        end
    end
    
    methods (Access = private)
        function obj= PulseStreamerClass()
            % Private default constructor.
            Initialize(obj)
        end
    end
    methods (Access = public)
        
        function Initialize(obj)
            obj.ps = PulseStreamer('132.64.56.49');
            obj.newSequence;
        end
    end
    methods % prepare and run
        function channelNames = get.channelNames(obj)
            channelNames = obj.channelNamesPrivate;
        end
        function channelValues = get.channelValues(obj)
            channelValues = obj.channelValuesPrivate;
        end
        function duration = get.duration(obj)
            duration = obj.durationPrivate;
        end
        function time = get.time(obj)
            time = cumsum(obj.durationPrivate);
        end
        function nickname = get.nickname(obj)
            nickname = obj.nicknamePrivate;
        end
        
        function sequence = get.sequence(obj)
            sequence = obj.sequencePrivate;
        end
        function repeats = get.repeats(obj)
            repeats = obj.repeatsPrivate;
        end
        function setRepeats(obj,newVal)
            if newVal<1 || newVal> obj.maxRepeats
                error('Value out of range')
            end
            obj.repeatsPrivate = newVal;
        end
    end
    methods
        function newSequence(obj)
            obj.durationPrivate = []; %mus
            obj.nicknamePrivate = {};
            obj.sequencePrivate = [];
        end
        function newSequenceLine(obj,newEvent,newDuration,nickname)
            if nargin<4 || isempty(nickname)
                nickname = {''};
            end
            [~,newChannels] = obj.ChannelValuesFromNames(newEvent);
            if length(newDuration) > 1 || isempty(newDuration)
                error('invalid input duration')
            end
            if newDuration < obj.minDuration || newDuration > obj.maxDuration
                error('Duration must be between %s and %s',num2str(obj.minDuration),num2str(obj.maxDuration))
            end
            obj.durationPrivate = [obj.durationPrivate, newDuration];
            obj.sequencePrivate = [obj.sequencePrivate, newChannels];
            obj.nicknamePrivate = {obj.nicknamePrivate ,nickname};
        end
        
        function addEventAtGivenTime(obj,newTime,newEvent,newDuration) %no nickname here!
            minTime = -1000; 
            maxTime = max(1e4, sum(obj.duration)*2);
            dif = 1e-10;
            
            %newNickname = {''};
            
            [~, newEvent] = obj.ChannelValuesFromNames(newEvent);
            if length(newDuration) > 1 || isempty(newDuration) || length(newTime) > 1 || isempty(newTime)
                error('invalid input duration / initial time')
            end
            if newDuration < obj.minDuration || newDuration > obj.maxDuration
                error('Duration must be between %s and %s',num2str(obj.minDuration),num2str(obj.maxDuration))
            end
            if newTime < minTime || newTime > maxTime
                error('Duration must be between %s and %s \mus',num2str(minTime),num2str(maxTime))
            end
            localDuration= obj.durationPrivate;
            localSequence = obj.sequencePrivate;
            localNickname = obj.nicknamePrivate;
            ch = size(localSequence,1); % number of PB channels in the system
            %%%%%%%%%%%%%%%%
            if newTime<0 % add a new empty line, and continue
                localDuration = [abs(newTime), localDuration];
                localSequence = [zeros(ch,1),localSequence];
                localNickname = [localNickname,{''}];
                newTime = 0;
            end
            k = 1;
            while k <=length(localDuration) && newDuration > dif
                tInitial = sum(localDuration(1:k-1));
                tFinal = tInitial + localDuration(k);
                if newTime - tInitial < dif
                    if newDuration < localDuration(k) %Split event and run again
                        localSequence = localSequence(:,[1:k,k:end]);
                        localDuration = [localDuration(1:k-1), newDuration, localDuration(k) - newDuration, localDuration(k+1:end)];
                        localNickname = [localNickname(1:k-1),{'changed'},{'changed'},localNickname(k+1:end)];
                    else %add the part needed, and pass the reminder to the next event
                        localSequence(:,k) = (localSequence(:,k) + newEvent ~= 0);
                        newDuration = newDuration - localDuration(k);
                        newTime = newTime + localDuration(k);
                        k = k +1;
                    end
                else
                    if newTime - tFinal < -dif % separate the original event into two parts, and continues
                        localSequence = localSequence(:,[1:k, k:end]);
                        localDuration = [localDuration(1:k-1), newTime-tInitial,tFinal-newTime, localDuration(k+1:end)];%split the k'th event time. changes will be made in the last one
                        localNickname = [localNickname(1:k-1), {'changed'}, {'changed'}, localNickname(k+1:end)];
                    end
                    k = k + 1;
                end
            end
            tFinal = sum(localDuration);
            if newDuration
                if newTime - tFinal > 0
                    localDuration = [localDuration, newTime - tFinal];
                    localSequence = [localSequence,zeros(ch,1)];
                    localNickname = [localNickname,{''}];
                end
                localDuration = [localDuration, newDuration];
                localSequence = [localSequence,newEvent];
                localNickname = [localNickname,{''}];
            end
            obj.durationPrivate = localDuration;
            obj.sequencePrivate = localSequence;
            obj.nicknamePrivate = localNickname;          
        end
        function changeSequence(obj,index,what,newValue)
            index = obj.indexFromNickname(index);
            switch lower(what)
                case {'duration','t'}
                    if newValue < obj.minDuration || newValue > obj.maxDuration
                        error('Duration must be between %s and %s',num2str(obj.minDuration),num2str(obj.maxDuration))
                    end
                    obj.durationPrivate(index) = newValue;
                case {'sequence','event','pb'}
                    [~,newChannels] = obj.ChannelValuesFromNames(newValue);
                    obj.sequencePrivate(:,index) = newChannels;
                otherwise
                    error('Unknown option')
            end
        end
        function setChannelNameAndValue(obj,names,values)
            if size(names)~=size(values)
                error('inputs must be of the same size')
            end
            if ~isa(names,'cell')
                error('Input ''name'' must be of class ''cell''')
            end
            if ~isnumeric(values)
                error('Input ''values'' must be a numeric input')
            end
            if length(unique(names)) ~= length(names)
                error('input ''names'' has repeats in it. A single name must be given to each channel')
            end
            if length(unique(values)) ~= length(values)
                error('input ''values'' has repeats in it. A single name must be given to each channel')
            end
            values = round(values);
            obj.channelValuesPrivate = values;
            obj.channelNamesPrivate = names;
        end
    end
    
    methods
        function On(obj,channels)
            % OutPuts - channels to be opened (0,1,2,,,,), as a double
            % vector            
            channels = obj.ChannelValuesFromNames(channels); %converts from a cell of names to channel numbers, if needed
            if isempty(channels)
                channels = 0;
            else
                if sum(rem(channels,1)) || min(channels) <0 || max(channels)> obj.maxPBchannel
                    error('Input must be integers from 0 to %f', obj.maxPBchannel)
                end
                channels = sum(2.^channels);
            end
            
            output = OutputState(channels,0,0);
            obj.ps.constant(output);
        end
        function Off(obj)
            output = OutputState(0,0,0);
            obj.ps.constant(output);
        end
        
        function Run(obj)
            obj.ps.startNow;
        end
        
        function sequences = uploadSequence(obj)
            %duration: event duration, in ns;
            %channels: a vector of the channel numbers
            %events: a (logical) matrix of length(channels) * length(duration).
            % The input can also be a cell with N inputs, each one
            % containing the PB to be turned on (empty for non)
            

            if isempty(obj.sequencePrivate)
                error('Upload sequence')
            end
            
            outputZero = OutputState(0,0,0);
            initialOutputState = outputZero;
            finalOutputState = outputZero;
            underflowOutputState = outputZero;
            start = PSStart.Software;
            
            % settings for sequence generation
            numberOfSequences = length(obj.durationPrivate);
            sequences = [];
            for i=1:numberOfSequences
                sequences = sequences + P(obj.durationPrivate(i)*1e3, obj.sequencePrivate(:,i)', 0, 0);
            end
            obj.ps.stream(sequences, obj.repeatsPrivate, initialOutputState, finalOutputState, underflowOutputState, start);
        end
    end
    
    methods 
        function [j]= Index(obj,channel)
            %recives either channel's name or number
            %returnes the channels location in channelPrivate
            if iscell(channel)
                j=obj.channelPrivate(strcmp(channel,obj.NamePrivate));
            elseif isnumeric(channel)
                j=obj.channelPrivate(obj.channelPrivate==channel);
            else
                error('couldnt find the PB channel');
            end
            
        end
    end
    
    methods (Access = private)
        function [chanNum,chanIndex] = ChannelValuesFromNames(obj,names)
            % inputs: a cell of chars / a char / a vector of integers. In
            % the former two - converts the name to the correspondin PB
            % channel number/s (chenNum). In the latter - check values are OK and returns them. In empty - chenNum = [];
            % Also returns a vector with 1 for the channels detected, and 0
            % elsewere.
            chanIndex = zeros(length(obj.channelValues),1);
            if nargin<2 || isempty(names) || isequal(names,'')
                chanNum = [];
            else
                switch class(names)
                    case 'cell'
                        index = 1;
                        chanNum = zeros(size(names));
                        for k = 1:length(names)
                            p = strcmp(names{k},obj.channelNames)';                         
                            if ~nnz(p)
                                warning('Unknown PB channelname %s',names{k})
                            else
                                chanNum(index) = obj.channelValues(p);
                                chanIndex = chanIndex + p;
                                index = index + 1;
                            end
                        end
                    case 'char'
                        p = strcmp(names,obj.channelNames);
                        chanNum = obj.channelValues(p);
                        chanIndex(:) = p;
                    case 'double'
                        if sum(rem(names,1))
                            error('input must be an integer')
                        elseif sum(names<0) || sum(names > 16)
                            error('Value out of range')
                        end                     
                        chanNum = names;
                        for k = 1:length(chanNum)
                            p = (chanNum(k) == obj.channelValues);
                            if ~nnz(p)
                                warning('Channel # %u was not found in PS class',chanNum(k))
                            else
                                chanIndex = chanIndex + p;
                            end
                        end
                    otherwise
                        error('Unknown class')
                end
            end
        end
        function index = indexFromNickname(obj,nickname)
            if isnumeric(nickname)
                index = nickname;
            elseif isa(nickname,'char')
                index = strcmp(nickname,obj.nicknamePrivate);
            else
                error('unknown kind')
            end
            if isempty(index) || ~nnz(index)
                    error('index not found')
            end
        end
    end
end