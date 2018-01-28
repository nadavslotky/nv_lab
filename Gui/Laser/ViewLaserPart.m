classdef ViewLaserPart < ViewHBox & EventListener
    % VIEWLASERLASER GUI component that handles a laser part
    % could be the aom controller for the laser, or the laser source controller
    properties
        %%%% UI related %%%
        cbxEnabled             % check box
        edtPowerPercentage     % edit-text
        sliderPower            % slider
        
        %%%% the laser part name (to send requests and to listen to) %%%%
        mLaserPartName
    end
    
    methods
        
        %% constructor
        function obj = ViewLaserPart(parent, controller, laserPartPhysical, nameToDisplay)
            % parent - gui component
            % controller - the main GUI controller
            % laserPartPhysical - object of derived from LaserPartAbstract 
            % (LaserPartAbstract is in the folder Physical\Laser)
            
            %%%%%%%% init variables %%%%%%%%
            nameToListen = laserPartPhysical.name;
            
            %%%%%%%% Constructors %%%%%%%%
            obj@EventListener(nameToListen);
            obj@ViewHBox(parent, controller);
            
            %%%%%%%% the laser physics object %%%%%%%%
            obj.mLaserPartName = nameToListen;
            
            
            % UI components init
            partRow = obj.component;
            partRow.Spacing = 5;            
            
%             label = uicontrol('Parent', partRow, obj.PROP_LABEL{:}, 'String', nameToDisplay); % obj.headerProps got by inheritance from GuiComponent %
%             labelWidth = obj.getWidth(label);
            
            obj.cbxEnabled = uicontrol(obj.PROP_CHECKBOX{:}, 'Parent', partRow, ...
                'String', nameToDisplay, ...
                'Callback', @obj.cbxEnabledCallback);
            obj.edtPowerPercentage = uicontrol(obj.PROP_EDIT{:}, 'Parent', partRow);
            obj.sliderPower = uicontrol(obj.PROP_SLIDER{:}, 'Parent', partRow);
            
            widths = [70, 50, 150];
            set(partRow, 'Widths', widths);
            
            
            %%%%%%%% UI components set values  %%%%%%%%
            obj.width = sum(widths) + 20;
            obj.height = 30;            
            
            
            % Set functionality for "setEnabled" and "setValue" %%%%%%%%
            if ~laserPartPhysical.canSetEnabled
                obj.cbxEnabled.Enable = 'off';
            end
            
            if laserPartPhysical.canSetValue
                set(obj.sliderPower, 'Callback', @obj.sliderPowerCallback, ...
                    'Visible', 'on');
                set(obj.edtPowerPercentage, 'Callback', @obj.edtPowerPercentageCallback, ...
                    'Enable', 'on');
            else
                obj.sliderPower.Enable = 'off';
                obj.edtPowerPercentage.Enable = 'off';
            end
            
            obj.refresh();
        end
        
        
        %%%% Callbacks %%%%
        function edtPowerPercentageCallback(obj, ~, ~)
            newValue = obj.edtPowerPercentage.String;
            newValue = cell2mat(regexp(newValue,'^-?\d+','match'));  % leave only digits (maybe proceeded by a minus sign)
            newValue = str2double(newValue);
            obj.requestNewValue(newValue);
        end
        
        function sliderPowerCallback(obj, ~, ~)
            newValue = get(obj.sliderPower,'Value');
            % newValue now is in [0, 1]
            obj.requestNewValue(round(newValue * 100));
        end
        
        function cbxEnabledCallback(obj, ~, ~)
            obj.requestNewEnabled(get(obj.cbxEnabled, 'Value'));
        end
        
    end
    
    methods (Access = protected)
        
        function refresh(obj)
            obj.setValueInternally(obj.laserPart.currentValue);
            obj.setEnabledInternally(obj.laserPart.isEnabled);
        end
        
        % Internal setter for the new value
        function out = setValueInternally(obj, newLaserValue)
            % newLaserValue - double. Between [0,100]
            set(obj.edtPowerPercentage, 'String', strcat(num2str(newLaserValue),'%'));
            set(obj.sliderPower, 'Value', newLaserValue/100);
            out = true;
        end
        
        % Internal function for changing the checkbox "enabled"
        function setEnabledInternally(obj, newBoolValueEnabled)
            set(obj.cbxEnabled, 'Value', newBoolValueEnabled);
        end % function setLaserEnabled
		
		function laserPartObject = laserPart(obj)
			% get the laser part
			laserPartObject = getObjByName(obj.mLaserPartName);
		end
        
    end  % methods
    
    %% These methods actually request stuff from the physics. Carefull!
    methods (Access = protected)
        function requestNewValue(obj, newValue)
            obj.laserPart.setNewValue(newValue);
            % If the physics got our change - it will send an event to notify us
            % If not, it will send an error Event to notify us
        end
        
        function requestNewEnabled(obj, newBoolValue)
            obj.laserPart.setEnabled(newBoolValue);
            % If the physics got our change - it will send an event to notify us
            % If not, it will send an error Event to notify us
        end
    end
    
    %% Overriding methods!
    methods
        function onEvent(obj, event) %#ok<INUSD>
            % We don't need the event details. we can ask the details directly from the laser!
            obj.refresh();
        end
    end
    
end

