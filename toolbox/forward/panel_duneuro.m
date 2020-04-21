function varargout = panel_duneuro(varargin)
% PANEL_DUNEURO: DUNEuro options
%
% USAGE:  bstPanel = panel_duneuro('CreatePanel', OPTIONS)           : Call from the interactive interface
%         bstPanel = panel_duneuro('CreatePanel', sProcess, sFiles)  : Call from the process editor
%                s = panel_duneuro('GetPanelContents')

% @=============================================================================
% This function is part of the Brainstorm software:
% https://neuroimage.usc.edu/brainstorm
% 
% Copyright (c)2000-2020 University of Southern California & McGill University
% This software is distributed under the terms of the GNU General Public License
% as published by the Free Software Foundation. Further details on the GPLv3
% license can be found at http://www.gnu.org/copyleft/gpl.html.
% 
% FOR RESEARCH PURPOSES ONLY. THE SOFTWARE IS PROVIDED "AS IS," AND THE
% UNIVERSITY OF SOUTHERN CALIFORNIA AND ITS COLLABORATORS DO NOT MAKE ANY
% WARRANTY, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO WARRANTIES OF
% MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE, NOR DO THEY ASSUME ANY
% LIABILITY OR RESPONSIBILITY FOR THE USE OF THIS SOFTWARE.
%
% For more information type "brainstorm license" at command prompt.
% =============================================================================@
%
% Authors: Francois Tadel, 2020

eval(macro_method);
end


%% ===== CREATE PANEL =====
function [bstPanelNew, panelName] = CreatePanel(sProcess, sFiles) %#ok<DEFNU>
    panelName = 'DuneuroOptions';
    % Java initializations
    import java.awt.*;
    import javax.swing.*;

    % GUI CALL:  panel_duneuro('CreatePanel', OPTIONS)
    if (nargin == 1)
        OPTIONS = sProcess;
        % Check if there is only MEG, for simplified model by default
        isMegOnly = ~ismember('duneuro', {OPTIONS.EEGMethod, OPTIONS.ECOGMethod, OPTIONS.SEEGMethod});
    % PROCESS CALL:  panel_duneuro('CreatePanel', sProcess, sFiles)
    else
        OPTIONS = sProcess.options.duneuro.Value;
        % List of sensors
        Modalities = {'MEG MAG', 'MEG GRAD', 'MEG', 'EEG', 'ECOG', 'SEEG'};
        if ~isempty(sFiles(1).ChannelTypes)
            Modalities = intersect(sFiles(1).ChannelTypes, Modalities);
            if any(ismember({'MEG MAG','MEG GRAD'}, Modalities))
                Modalities = setdiff(Modalities, 'MEG');
            end
        end
        isMegOnly = all(ismember(Modalities, {'MEG', 'MEG MAG', 'MEG GRAD'}));
        % Get FEM files
        sSubject = bst_get('Subject', sFiles(1).SubjectFile);
        if isempty(sSubject.iFEM)
            error('No available FEM mesh file for this subject.');
        end
        OPTIONS.FemFile = file_fullpath(sSubject.Surface(sSubject.iFEM).FileName);
    end
    % Default options
%     defOPTIONS = bst_get('DuneuroOptions');
    defOPTIONS = duneuro_defaults();
    OPTIONS = struct_copy_fields(OPTIONS, defOPTIONS, 0);

    % ==== GET MESH INFO ====
    % Get the information from the head model
    fields = whos('-file', OPTIONS.FemFile);
    ivar = find(strcmpi({fields.name}, 'Elements'));
    if isempty(ivar)
        error(['Invalid FEM mesh: missing field "Elements" in "' OPTIONS.FemFile '".']);
    end
    switch fields(ivar).size(2)
        case 4,    ElementType = 'tetrahedron';
        case 8,    ElementType = 'hexahedron';
        otherwise, error('Mesh element type is not defined');
    end
    % Load tissue labels
    FemMat = load(OPTIONS.FemFile, 'TissueLabels');
    % Get default conductivities
    OPTIONS.FemNames = FemMat.TissueLabels;
    OPTIONS.FemCond = GetDefaultCondutivity(OPTIONS.FemNames);
    
    % EEG: Select all layers; MEG: Select only the innermost layer
    if isMegOnly
        OPTIONS.FemSelect = zeros(size(OPTIONS.FemCond));
        OPTIONS.FemSelect(1) = 1;
    else
        OPTIONS.FemSelect = ones(size(OPTIONS.FemCond));
    end
    
    
    % ==== FRAME STRUCTURE ====
    % Create main panel: split in top (interface) / left(standard options) / right (details)
    jPanelNew = gui_component('panel');
    jPanelNew.setBorder(BorderFactory.createEmptyBorder(12,12,12,12));
    % Create top panel
    jPanelTop = gui_river([1,1], [0,6,6,6]);
    jPanelNew.add(jPanelTop, BorderLayout.NORTH);
    % Create left panel
    jPanelLeft = java_create('javax.swing.JPanel');
    jPanelLeft.setLayout(GridBagLayout());
    jPanelNew.add(jPanelLeft, BorderLayout.WEST);
    % Create right panel
    jPanelRight = java_create('javax.swing.JPanel');
    jPanelRight.setLayout(GridBagLayout());
    jPanelRight.setBorder(BorderFactory.createEmptyBorder(0,12,0,0));
    jPanelNew.add(jPanelRight, BorderLayout.EAST);
    % Default constrains
    c = GridBagConstraints();
    c.fill    = GridBagConstraints.HORIZONTAL;
    c.weightx = 1;
    c.weighty = 0;
    
    % ======================================================================================================

    % ===== PANEL LEFT: FEM LAYERS =====
    jPanelLayers = gui_river([2,2], [0,6,6,6], 'FEM layers & conductivities');
        nLayers = length(OPTIONS.FemNames);
        jCheckLayer = javaArray('javax.swing.JCheckBox', nLayers);
        jTextCond   = javaArray('javax.swing.JTextField', nLayers);
        % Loop on each layer
        for i = 1:nLayers
            % Add layer
            jCheckLayer(i) = gui_component('checkbox', jPanelLayers, 'br',  OPTIONS.FemNames{i}, [], [], @(h,ev)UpdatePanel(), []);
            jTextCond(i) = gui_component('texttime', jPanelLayers, 'tab', num2str(OPTIONS.FemCond(i), '%g'), [], [], [], []);
            % Default selection of layers
            jCheckLayer(i).setSelected(OPTIONS.FemSelect(i));
        end
    c.gridy = 1;
    jPanelLeft.add(jPanelLayers, c);

    % ==== PANEL LEFT: FEM METHOD TYPE ====
    jPanelType = gui_river([1,1], [0,6,6,6], 'FEM method type');
        jGroupFemType = ButtonGroup();
        jRadioFemTypeFit   = gui_component('radio', jPanelType, 'br', 'Fitted',   jGroupFemType, '', [], []);
        jRadioFemTypeUnfit = gui_component('radio', jPanelType, 'br', 'Unfitted', jGroupFemType, '', [], []);
        switch lower(OPTIONS.FemType)
            case 'fitted',   jRadioFemTypeFit.setSelected(1);
            case 'unfitted', jRadioFemTypeUnfit.setSelected(1);
        end
    c.gridy = 2;
    jPanelLeft.add(jPanelType, c);
        
    % ==== PANEL LEFT: FEM SOLVER TYPE ====
    jPanelSolverType = gui_river([1,1], [0,6,6,6], 'FEM solver type');
        jGroupSolverType = ButtonGroup();
        jRadioSolverTypeCg = gui_component('radio', jPanelSolverType, 'br', 'CG: Continuous Galerkin',   jGroupSolverType, '', [], []);
        jRadioSolverTypeDg = gui_component('radio', jPanelSolverType, 'br', 'DG: Discontinuous Galerkin', jGroupSolverType, '', [], []);
        switch lower(OPTIONS.SolverType)
            case 'cg', jRadioSolverTypeCg.setSelected(1);
            case 'dg', jRadioSolverTypeDg.setSelected(1);
        end
    c.gridy = 3;
    jPanelLeft.add(jPanelSolverType, c);
    
    % ======================================================================================================
    
    % ==== PANEL RIGHT: FEM SOURCE MODEL ====
    jPanelSrcModel = gui_river([1,1], [0,6,6,6], 'FEM source model');
        jGroupSrcModel = ButtonGroup();
        jRadioSrcModelVen = gui_component('radio', jPanelSrcModel, 'br', 'Venant',              jGroupSrcModel, '', @(h,ev)UpdatePanel(1), []);
        jRadioSrcModelSub = gui_component('radio', jPanelSrcModel, 'br', 'Subtraction',         jGroupSrcModel, '', @(h,ev)UpdatePanel(1), []);
        jRadioSrcModelPar = gui_component('radio', jPanelSrcModel, 'br', 'Partial integration', jGroupSrcModel, '', @(h,ev)UpdatePanel(1), []);
        switch lower(OPTIONS.SrcModel)
            case 'venant',              jRadioSrcModelVen.setSelected(1);
            case 'subtraction',         jRadioSrcModelSub.setSelected(1);
            case 'partial_integration', jRadioSrcModelPar.setSelected(1);   
        end
    c.gridy = 1;
    jPanelRight.add(jPanelSrcModel, c);
    
    % ==== PANEL RIGHT: VENANT OPTIONS ====
    jPanelOptVen = gui_river([3,3], [0,6,6,6], 'Venant options');
        % Number of moments
        gui_component('label', jPanelOptVen, [], 'Number of moments (1-5): ', [], '', [], []);
        jTextNbMoments = gui_component('texttime', jPanelOptVen, 'tab', '', [], '', [], []);
        gui_validate_text(jTextNbMoments, [], [], 1:5, '', 0, OPTIONS.SrcNbMoments, []);
        % Reference length
        gui_component('label', jPanelOptVen, 'br', 'Reference length (1-100): ', [], '', [], []);
        jTextRefLen = gui_component('texttime', jPanelOptVen, 'tab', '', [], '', [], []);
        gui_validate_text(jTextRefLen, [], [], 1:100, '', 0, OPTIONS.SrcRefLen, []);
        % Weighting exponent
        gui_component('label', jPanelOptVen, 'br', 'Weighting exponent (1-3): ', [], '', [], []);
        jTextWeightExp = gui_component('texttime', jPanelOptVen, 'tab', '', [], '', [], []);
        gui_validate_text(jTextWeightExp, [], [], 1:3, '', 0, OPTIONS.SrcWeightExp, []);
        % Relaxation Factor
        gui_component('label', jPanelOptVen, 'br', 'Relaxation Factor (1e-3, 1e-9): ', [], '', [], []);
        jTextRelaxFactor = gui_component('text', jPanelOptVen, 'tab', sprintf('%e', OPTIONS.SrcRelaxFactor), [], '', [], []);
        % gui_validate_text(jTextWeightExp, [], [], 1:3, '', 0, OPTIONS.SrcRelaxFactor, []);
        % Mixed moments
        jCheckMixedMoments = gui_component('checkbox', jPanelOptVen, 'br', 'Mixed moments', [], '', [], []);
        if (OPTIONS.SrcMixedMoments == 1)
            jCheckMixedMoments.setSelected(1);
        end
        % Restrict
        jCheckRestrict = gui_component('checkbox', jPanelOptVen, 'br', 'Restrict', [], '', [], []);
        if (OPTIONS.SrcRestrict == 1)
            jCheckRestrict.setSelected(1);
        end
    c.gridy = 2;
    jPanelRight.add(jPanelOptVen, c);
    
    % ==== PANEL RIGHT: SUBTRACTION OPTIONS ====
    jPanelOptSub = gui_river([3,3], [0,6,6,6], 'Subtraction options');
        % Number of moments
        gui_component('label', jPanelOptSub, [], 'intorderadd (1-5): ', [], '', [], []);
        jTextIntorderadd = gui_component('texttime', jPanelOptSub, 'tab', '', [], '', [], []);
        gui_validate_text(jTextIntorderadd, [], [], 0:5, '', 0, OPTIONS.SrcIntorderadd, []);
        % Number of moments
        gui_component('label', jPanelOptSub, 'br', 'intorderadd_lb (1-5): ', [], '', [], []);
        jTextIntorderadd_lb = gui_component('texttime', jPanelOptSub, 'tab', '', [], '', [], []);
        gui_validate_text(jTextIntorderadd_lb, [], [], 0:5, '', 0, OPTIONS.SrcIntorderadd_lb, []);
    c.gridy = 3;
    jPanelRight.add(jPanelOptSub, c);
    
    % ==== PANEL RIGHT: INPUT OPTIONS ====
    jPanelInput = gui_river([1,1], [0,6,6,6], 'Input options');
        % Shrink source space
        gui_component('label', jPanelInput, '', 'Shrink source space: ', [], '', [], []);
        jTextSrcShrink = gui_component('texttime', jPanelInput, '', '', [], '', [], []);
        gui_validate_text(jTextSrcShrink, [], [], {0,100,100}, '', 0, OPTIONS.SrcShrink, []);
        gui_component('label', jPanelInput, '', '  mm');
    c.gridy = 4;
    jPanelRight.add(jPanelInput, c);
    
    % ==== PANEL RIGHT: OUTPUT OPTIONS ====
    jPanelOutput = gui_river([1,1], [0,6,6,6], 'Output options');
        % Save transfer matrix
        jCheckSaveTransfer = gui_component('checkbox', jPanelOutput, '', 'Save transfer matrix', [], '', [], []);
        if (OPTIONS.BstSaveTransfer)
            jCheckSaveTransfer.setSelected(1);
        end
    c.gridy = 5;
    jPanelRight.add(jPanelOutput, c);
    
    % ===== VALIDATION BUTTONS =====
    jPanelValid = gui_river([1,1], [12,6,6,6]);
    % Add a glue at the bottom of the right panel (for appropriate scaling with the left)
    c.gridy   = 6;
    c.weighty = 1;
    jPanelRight.add(Box.createVerticalGlue(), c);
    % Add a glue at the bottom of the left panel (for appropriate scaling with the right)
    c.gridy   = 7;
    c.weighty = 1;
    jPanelLeft.add(Box.createVerticalGlue(), c);
    % Expert/normal mode
    jButtonExpert = gui_component('button', jPanelValid, [], 'Show details', [], [], @SwitchExpertMode_Callback, []);
    gui_component('label', jPanelValid, 'hfill', ' ');
    % Ok/Cancel
    gui_component('Button', jPanelValid, 'right', 'Cancel', [], [], @ButtonCancel_Callback, []);
    gui_component('Button', jPanelValid, [],      'OK',     [], [], @ButtonOk_Callback,     []);
    c.gridy = 4;
    c.weighty = 0;
    jPanelLeft.add(jPanelValid, c);
    
    % ===== PANEL CREATION =====
    % Return a mutex to wait for panel close
    bst_mutex('create', panelName);
    % Create the BstPanel object that is returned by the function
    ctrl = struct('jCheckLayer',           jCheckLayer, ...
                  'jTextCond',             jTextCond, ...
                  'jRadioFemTypeFit',      jRadioFemTypeFit, ...
                  'jRadioFemTypeUnfit',    jRadioFemTypeUnfit, ...
                  'jRadioSolverTypeCg',    jRadioSolverTypeCg, ...
                  'jRadioSolverTypeDg',    jRadioSolverTypeDg, ...
                  'jRadioSrcModelVen',     jRadioSrcModelVen, ...
                  'jRadioSrcModelSub',     jRadioSrcModelSub, ...
                  'jRadioSrcModelPar',     jRadioSrcModelPar, ...
                  'jTextNbMoments',        jTextNbMoments, ...
                  'jTextRefLen',           jTextRefLen, ...
                  'jTextWeightExp',        jTextWeightExp, ...
                  'jTextRelaxFactor',      jTextRelaxFactor, ...
                  'jCheckMixedMoments',    jCheckMixedMoments, ...
                  'jCheckRestrict',        jCheckRestrict, ...
                  'jTextIntorderadd',      jTextIntorderadd, ...
                  'jTextIntorderadd_lb',   jTextIntorderadd_lb, ...
                  'jTextSrcShrink',        jTextSrcShrink, ...
                  'jCheckSaveTransfer',    jCheckSaveTransfer);
    ctrl.FemNames = OPTIONS.FemNames;
    % Create the BstPanel object that is returned by the function
    bstPanelNew = BstPanel(panelName, jPanelNew, ctrl);
    % Update comments
    UpdatePanel(1);
    


%% =================================================================================
%  === LOCAL CALLBACKS  ============================================================
%  =================================================================================
    %% ===== BUTTON: CANCEL =====
    function ButtonCancel_Callback(varargin)
        % Close panel
        gui_hide(panelName);
    end

    %% ===== BUTTON: OK =====
    function ButtonOk_Callback(varargin)
        % Release mutex and keep the panel opened
        bst_mutex('release', panelName);
    end

    %% ===== SWITCH EXPERT MODE =====
    function SwitchExpertMode_Callback(varargin)
        % Toggle expert mode
        ExpertMode = bst_get('ExpertMode');
        bst_set('ExpertMode', ~ExpertMode);
        % Update comment
        UpdatePanel(1);
    end
    

    %% ===== UPDATE PANEL ======
    % USAGE:  UpdatePanel(isForced = 0)
    function UpdatePanel(isForced)
        % Default values
        if (nargin < 1) || isempty(isForced)
            isForced = 0;
        end
        % Expert mode / Normal mode
        if isForced
            ExpertMode = bst_get('ExpertMode');
            % Show/hide panels
            jPanelRight.setVisible(ExpertMode);
            jPanelType.setVisible(ExpertMode);
            jPanelSolverType.setVisible(ExpertMode);
            jPanelSrcModel.setVisible(ExpertMode);
            jPanelOptVen.setVisible(ExpertMode && jRadioSrcModelVen.isSelected());
            jPanelOptSub.setVisible(ExpertMode && jRadioSrcModelSub.isSelected());
            jPanelInput.setVisible(ExpertMode);
            jPanelOutput.setVisible(ExpertMode);
            % Update expert button 
            if ExpertMode
                jButtonExpert.setText('Hide details');
            else
                jButtonExpert.setText('Show details');
            end            
            % Get old panel
            [bstPanelOld, iPanel] = bst_get('Panel', 'DuneuroOptions');
            container = get(bstPanelOld, 'container');
            % Re-pack frame
            if ~isempty(container)
                jFrame = container.handle{1};
                if ~isempty(jFrame)
                    jFrame.pack();
                end
            end
        end
        % FEM Layers
        for j = 1:nLayers
            jTextCond(j).setEnabled(jCheckLayer(j).isSelected());
        end
    end
end


%% =================================================================================
%  === EXTERNAL CALLBACKS  =========================================================
%  =================================================================================
%% ===== GET PANEL CONTENTS =====
function s = GetPanelContents() %#ok<DEFNU>
    % Get panel controls handles
    ctrl = bst_get('PanelControls', 'DuneuroOptions');
    if isempty(ctrl)
        s = [];
        return; 
    end
    % Get default duneuro options
    s = duneuro_defaults();
    
    % FEM layers
    for i = 1:length(ctrl.jCheckLayer)
        s.FemSelect(i) = ctrl.jCheckLayer(i).isSelected();
        s.FemCond(i) = str2double(char(ctrl.jTextCond(i).getText()));
    end
    % FEM method type
    if ctrl.jRadioFemTypeFit.isSelected()
        s.FemType = 'fitted';
    elseif ctrl.jRadioFemTypeUnfit.isSelected()
        s.FemType = 'unfitted';
    end
    % FEM solver type
    if ctrl.jRadioSolverTypeCg.isSelected()
        s.SolverType = 'cg';
    elseif ctrl.jRadioSolverTypeDg.isSelected()
        s.SolverType = 'dg';
    end
    % Source model
    if ctrl.jRadioSrcModelVen.isSelected()
        s.SrcModel = 'venant';
    elseif ctrl.jRadioSrcModelSub.isSelected()
        s.SrcModel = 'subtraction';
    elseif ctrl.jRadioSrcModelPar.isSelected()
        s.SrcModel = 'partial_integration';
    end
    % Venant options
    if strcmpi(s.SrcModel, 'venant')
        s.SrcNbMoments    = str2double(ctrl.jTextNbMoments.getText());
        s.SrcRefLen       = str2double(ctrl.jTextRefLen.getText());
        s.SrcWeightExp    = str2double(ctrl.jTextWeightExp.getText());
        s.SrcRelaxFactor  = str2double(ctrl.jTextRelaxFactor.getText());
        s.SrcMixedMoments = ctrl.jCheckMixedMoments.isSelected();
        s.SrcRestrict     = ctrl.jCheckRestrict.isSelected();
    % Subtraction options
    elseif strcmpi(s.SrcModel, 'subtraction')
        s.SrcIntorderadd    = str2double(ctrl.jTextIntorderadd.getText());
        s.SrcIntorderadd_lb = str2double(ctrl.jTextIntorderadd_lb.getText());
    end
    % Input options
    s.SrcShrink = str2double(ctrl.jTextSrcShrink.getText());
    % Output options
    s.BstSaveTransfer = ctrl.jCheckSaveTransfer.isSelected();
end


%% ===== GET DEFAULT CONDUCTIVITIES =====
function FemCond = GetDefaultCondutivity(FemNames, Reference)
    % Default reference
    if (nargin < 2) || isempty(Reference)
        Reference = 'simbio';
    end
    % Default conductivity values
    switch (Reference)
        case 'simbio'
            conductivity = [0.14, 0.33, 1.79, 0.025, 0.008, 0.43];
        case 'simnibs'
            conductivity = [0.126, 0.275, 1.654, 0.010, 0.465];  % SimNIBS paper & soft
    end
    % By default: conductivity of the grey matter
    FemCond = conductivity(2) * ones(1, length(FemNames));
    % Detect the conductivity layer by name
    for i = 1:length(FemNames)
        if ~isempty(strfind(FemNames{i}, 'white')) || ~isempty(strfind(FemNames{i}, 'wm'))
            FemCond(i) = conductivity(1);
        elseif ~isempty(strfind(FemNames{i}, 'brain')) || ~isempty(strfind(FemNames{i}, 'grey')) || ~isempty(strfind(FemNames{i}, 'gray')) || ~isempty(strfind(FemNames{i}, 'gm')) || ~isempty(strfind(FemNames{i}, 'cortex'))
            FemCond(i) = conductivity(2);
        elseif ~isempty(strfind(FemNames{i}, 'csf')) || ~isempty(strfind(FemNames{i}, 'inner'))
            FemCond(i) = conductivity(3);
        elseif ~isempty(strfind(FemNames{i}, 'spong')) % 'Skull spongia'
            FemCond(i) = conductivity(5);
        elseif ~isempty(strfind(FemNames{i}, 'bone')) || ~isempty(strfind(FemNames{i}, 'skull')) || ~isempty(strfind(FemNames{i}, 'outer'))  % 'Skull compacta'
            FemCond(i) = conductivity(5);
        elseif ~isempty(strfind(FemNames{i}, 'skin')) || ~isempty(strfind(FemNames{i}, 'scalp')) || ~isempty(strfind(FemNames{i}, 'head'))
            FemCond(i) = conductivity(6);
        end
    end
end




