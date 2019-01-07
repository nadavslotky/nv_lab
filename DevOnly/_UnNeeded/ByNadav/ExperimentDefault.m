classdef ExperimentDefault < Experiment
    %EXPDEFAULT Default experiment, to be run before any actual experiment
    %           starts
    
    properties (Constant, Hidden)
        EXP_NAME = '';
    end
    
    methods
        function obj = ExperimentDefault()
            obj@Experiment;
        end
        
        function prepare(obj) %#ok<*MANU>
        end
        
        function perform(obj)
        end
        
        function wrapUp(obj)
        end
        
        function normalizedData(obj)
        end
    end
    
end
