classdef ViewImageResultPanelCursor < GuiComponent
    %VIEWSTAGESCANPANELPLOT panel for the cursor
    %   Detailed explanation goes here
    
    properties
        radioMarker
        radioZoom
        radioLocation
        
        dataCursor = [];
    end
    
    methods
        function obj = ViewImageResultPanelCursor(parent, controller)
            obj@GuiComponent(parent, controller);
            %             panel = uix.Panel('Parent', parent.component,'Title','Colormap', 'Padding', 5);
            bgMain = uibuttongroup(...
                'parent', parent.component, ...
                'Title', 'Cursor', ...
                'SelectionChangedFcn',@obj.callbackRadioSelection);
            obj.component = bgMain;
            
            rbHeight = 15; % "rb" stands for "radio button"
            rbWidth = 70;
            paddingFromLeft = 10;
            
            obj.radioMarker = uicontrol(obj.PROP_RADIO{:}, 'Parent', bgMain, ...
                'String', 'Marker', ...
                'Position', [paddingFromLeft 60 rbWidth rbHeight]);
            obj.radioZoom = uicontrol(obj.PROP_RADIO{:}, 'Parent', bgMain, ...
                'String', 'Zoom', ...
                'Position', [paddingFromLeft 35 rbWidth rbHeight]);
            obj.radioLocation = uicontrol(obj.PROP_RADIO{:}, 'Parent', bgMain, ...
                'String', 'Move to', ...
                'Position', [paddingFromLeft 10 rbWidth rbHeight]);
            
            obj.height = 100;
            obj.width = 90;
        end
        
        function update(obj)
            % Executes when image updates
            obj.component.SelectedObject = obj.radioMarker;
            obj.updatePrivate;
        end
        
        %%%% Callbacks %%%%
        function callbackRadioSelection(obj, ~, event)
            if isempty(obj.dataCursor)
                return
            end
            selection = event.NewValue;
            obj.dataCursor.ClearCursorData;
            obj.updatePrivate(selection);
        end
        
        function radioMarkerCallback(obj)
            % display cursor with specific data tip
            datacursormode on;
            obj.dataCursor.setUpdateFcn;
        end
        function radioZoomCallback(obj)
            % Creates a rectangle on the selected area, and updates the
            % GUI's min and max values accordingly
            obj.dataCursor.UpdataDataByZoom;
            obj.backToMarker;
        end
        function radioLocationCallback(obj)
            % Draws horizontal and vertical line on the selected
            % location, and moves the stage to this location.
            datacursormode off;
            img = imhandles(obj.dataCursor.vAxes);
            set(img, 'ButtonDownFcn', @obj.setLocationAndFinish);
        end
    end
    
    methods (Access = private)
        function updatePrivate(obj,selectedRadioButton)
            % Internal function for update
            % Specificly, it does not change the SelectedObject property
            
            %%%% Draw crosshairs: %%%%
            % get graphical axes
            resultImage = getObjByName(ViewImageResultImage.NAME);
            gAxes = resultImage.vAxes;
            % get stage position
            scanner = getObjByName(StageScanner.NAME);
            stage = getObjByName(scanner.mStageName);
            phAxes = scanner.mStageScanParams.getScanAxes;
            pos = stage.Pos(phAxes);
            % draw
            if isempty(obj.dataCursor)
                obj.dataCursor = DataCursor(resultImage);
            end
            obj.dataCursor.drawCrosshairs(axis(gAxes),pos)
            
            %%%% Set selected option callback
            if ~exist('selectedRadioButton','var')
                selectedRadioButton = obj.component.SelectedObject;
            end
            switch selectedRadioButton
                case obj.radioMarker
                    obj.radioMarkerCallback;
                case obj.radioZoom
                    obj.radioZoomCallback;
                case obj.radioLocation
                    obj.radioLocationCallback;
                otherwise
                    EventStation.anonymousError('This should not have happenned')
            end
        end
        
        function setLocationAndFinish(obj, ~, ~)
            obj.dataCursor.setLocationFromCursor;
%             obj.backToMarker;
        end
        
        function backToMarker(obj)
            % when other operations finish, we want to return the cursor to
            % "marker" mose, both visually and functionally
            obj.radioMarker.Value = 1;  % visually (#1 is the marker option)
            obj.radioMarkerCallback;    % functionally
        end
    end
end
