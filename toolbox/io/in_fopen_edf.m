function [sFile, ChannelMat] = in_fopen_edf(DataFile, ImportOptions)
% IN_FOPEN_EDF: Open a BDF/EDF file (continuous recordings)
%
% USAGE:  [sFile, ChannelMat] = in_fopen_edf(DataFile, ImportOptions)

% @=============================================================================
% This function is part of the Brainstorm software:
% http://neuroimage.usc.edu/brainstorm
% 
% Copyright (c)2000-2016 University of Southern California & McGill University
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
% Authors: Francois Tadel, 2012-2015
        

% Parse inputs
if (nargin < 2) || isempty(ImportOptions)
    ImportOptions = db_template('ImportOptions');
end


%% ===== READ HEADER =====
% Open file
fid = fopen(DataFile, 'r', 'ieee-le');
if (fid == -1)
    error('Could not open file');
end
% Read all fields
hdr.version    = fread(fid, [1  8], 'uint8=>char');  % Version of this data format ('0       ' for EDF, [255 'BIOSEMI'] for BDF)
hdr.patient_id = fread(fid, [1 80], '*char');  % Local patient identification
hdr.rec_id     = fread(fid, [1 80], '*char');  % Local recording identification
hdr.startdate  = fread(fid, [1  8], '*char');  % Startdate of recording (dd.mm.yy)
hdr.starttime  = fread(fid, [1  8], '*char');  % Starttime of recording (hh.mm.ss) 
hdr.hdrlen     = str2double(fread(fid, [1 8], '*char'));  % Number of bytes in header record 
hdr.unknown1   = fread(fid, [1 44], '*char');             % Reserved ('24BIT' for BDF)
hdr.nrec       = str2double(fread(fid, [1 8], '*char'));  % Number of data records (-1 if unknown)
hdr.reclen     = str2double(fread(fid, [1 8], '*char'));  % Duration of a data record, in seconds 
hdr.nsignal    = str2double(fread(fid, [1 4], '*char'));  % Number of signals in data record
% Check file integrity
if isnan(hdr.nsignal) || isempty(hdr.nsignal) || (hdr.nsignal ~= round(hdr.nsignal)) || (hdr.nsignal < 0)
    error('File header is corrupted.');
end
% Read values for each nsignal
for i = 1:hdr.nsignal
    hdr.signal(i).label = strtrim(fread(fid, [1 16], '*char'));
end
for i = 1:hdr.nsignal
    hdr.signal(i).type = strtrim(fread(fid, [1 80], '*char'));
end
for i = 1:hdr.nsignal
    hdr.signal(i).unit = strtrim(fread(fid, [1 8], '*char'));
end
for i = 1:hdr.nsignal
    hdr.signal(i).physical_min = str2double(fread(fid, [1 8], '*char'));
end
for i = 1:hdr.nsignal
    hdr.signal(i).physical_max = str2double(fread(fid, [1 8], '*char'));
end
for i = 1:hdr.nsignal
    hdr.signal(i).digital_min = str2double(fread(fid, [1 8], '*char'));
end
for i = 1:hdr.nsignal
    hdr.signal(i).digital_max = str2double(fread(fid, [1 8], '*char'));
end
for i = 1:hdr.nsignal
    hdr.signal(i).filters = strtrim(fread(fid, [1 80], '*char'));
end
for i = 1:hdr.nsignal
    hdr.signal(i).nsamples = str2num(fread(fid, [1 8], '*char'));
end
for i = 1:hdr.nsignal
    hdr.signal(i).unknown2 = fread(fid, [1 32], '*char');
end
% Close file
fclose(fid);


%% ===== RECONSTRUCT INFO =====
% Individual signal gain
for i = 1:hdr.nsignal
    % Interpet units
    switch (hdr.signal(i).unit)
        case 'mV',                        unit_gain = 1e3;
        case {'uV', char([166 204 86])},  unit_gain = 1e6;
        otherwise,                        unit_gain = 1;
    end
    % Check min/max values
    if isempty(hdr.signal(i).digital_min) || isnan(hdr.signal(i).digital_min)
        disp(['EDF> Warning: The digitial minimum is not set for channel "' hdr.signal(i).label '".']);
        hdr.signal(i).digital_min = -2^15;
    end
    if isempty(hdr.signal(i).digital_max) || isnan(hdr.signal(i).digital_max)
        disp(['EDF> Warning: The digitial maximum is not set for channel "' hdr.signal(i).label '".']);
        hdr.signal(i).digital_max = -2^15;
    end
    if isempty(hdr.signal(i).physical_min) || isnan(hdr.signal(i).physical_min)
        disp(['EDF> Warning: The physical minimum is not set for channel "' hdr.signal(i).label '".']);
        hdr.signal(i).physical_min = hdr.signal(i).digital_min;
    end
    if isempty(hdr.signal(i).physical_max) || isnan(hdr.signal(i).physical_max)
        disp(['EDF> Warning: The physical maximum is not set for channel "' hdr.signal(i).label '".']);
        hdr.signal(i).physical_max = hdr.signal(i).digital_max;
    end
    if (hdr.signal(i).physical_min >= hdr.signal(i).physical_max)
        disp(['EDF> Warning: Physical maximum larger than minimum for channel "' hdr.signal(i).label '".']);
        hdr.signal(i).physical_min = hdr.signal(i).digital_min;
        hdr.signal(i).physical_max = hdr.signal(i).digital_max;
    end
    % Calculate and save channel gain
    hdr.signal(i).gain = unit_gain ./ (hdr.signal(i).physical_max - hdr.signal(i).physical_min) .* (hdr.signal(i).digital_max - hdr.signal(i).digital_min);
    % Error: The number of samples is not specified
    if isempty(hdr.signal(i).nsamples)
        % If it is not the first electrode: try to use the previous one
        if (i > 1)
            disp(['EDF> Warning: The number of samples is not specified for channel "' hdr.signal(i).label '".']);
            hdr.signal(i).nsamples = hdr.signal(i-1).nsamples;
        else
            error(['The number of samples is not specified for channel "' hdr.signal(i).label '".']);
        end
    end
    hdr.signal(i).sfreq = hdr.signal(i).nsamples ./ hdr.reclen;
end
% Preform some checks
if (hdr.nrec == -1)
    error('Cannot handle files where the number of recordings is unknown.');
end
% Find annotations channel
iAnnotChans = find(strcmpi({hdr.signal.label}, 'EDF Annotations'));   % Mutliple "EDF Annotation" channels allowed in EDF+
iStatusChan = find(strcmpi({hdr.signal.label}, 'Status'), 1);         % Only one "Status" channel allowed in BDF
iOtherChan = setdiff(1:hdr.nsignal, [iAnnotChans iStatusChan]);
% Get all the other channels
if isempty(iOtherChan)
    error('This file does not contain any data channel.');
end
% Read events preferencially from the EDF Annotations track
if ~isempty(iAnnotChans)
    iEvtChans = iAnnotChans;
elseif ~isempty(iStatusChan)
    iEvtChans = iStatusChan;
else
    iEvtChans = [];
end
% Detect channels with inconsistent sampling frenquency
iErrChan = find([hdr.signal(iOtherChan).sfreq] ~= hdr.signal(iOtherChan(1)).sfreq);
iErrChan = setdiff(iErrChan, iAnnotChans);
if ~isempty(iErrChan)
    error('Files with mixed sampling rates are not supported yet.');
end
% Detect interrupted signals (time non-linear)
hdr.interrupted = ischar(hdr.unknown1) && (length(hdr.unknown1) >= 5) && isequal(hdr.unknown1(1:5), 'EDF+D');
if hdr.interrupted
    warning('Interrupted EDF file ("EDF+D"): requires conversion to "EDF+C"');
end


%% ===== CREATE BRAINSTORM SFILE STRUCTURE =====
% Initialize returned file structure
sFile = db_template('sfile');
% Add information read from header
sFile.byteorder  = 'l';
sFile.filename   = DataFile;
if (uint8(hdr.version(1)) == uint8(255))
    sFile.format = 'EEG-BDF';
    sFile.device = 'BDF';
else
    sFile.format = 'EEG-EDF';
    sFile.device = 'EDF';
end
sFile.header = hdr;
% Comment: short filename
[tmp__, sFile.comment, tmp__] = bst_fileparts(DataFile);
% Consider that the sampling rate of the file is the sampling rate of the first signal
sFile.prop.sfreq   = hdr.signal(iOtherChan(1)).sfreq;
sFile.prop.samples = [0, hdr.signal(iOtherChan(1)).nsamples * hdr.nrec - 1];
sFile.prop.times   = sFile.prop.samples ./ sFile.prop.sfreq;
sFile.prop.nAvg    = 1;
% No info on bad channels
sFile.channelflag = ones(hdr.nsignal,1);


%% ===== PROCESS CHANNEL NAMES/TYPES =====
% Remove "-Ref" 
% Try to split the channel names in "TYPE NAME"
SplitType = repmat({''}, 1, hdr.nsignal);
SplitName = repmat({''}, 1, hdr.nsignal);
for i = 1:hdr.nsignal
    % Find space chars (label format "Type Name")
    iSpace = find(hdr.signal(i).label == ' ');
    % Only if there is one space only
    if (length(iSpace) == 1) && (iSpace >= 3)
        SplitName{i} = hdr.signal(i).label(iSpace+1:end);
        SplitType{i} = hdr.signal(i).label(1:iSpace-1);
    end
end
% Remove the classification if it makes some names non unique
uniqueNames = unique(SplitName);
for i = 1:length(uniqueNames)
    if ~isempty(uniqueNames{i})
        iName = find(strcmpi(SplitName, uniqueNames{i}));
        if (length(iName) > 1)
            [SplitName{iName}] = deal('');
            [SplitType{iName}] = deal('');
        end
    end
end


%% ===== CREATE EMPTY CHANNEL FILE =====
ChannelMat = db_template('channelmat');
ChannelMat.Comment = [sFile.device ' channels'];
ChannelMat.Channel = repmat(db_template('channeldesc'), [1, hdr.nsignal]);
% For each channel
for i = 1:hdr.nsignal
    % If is the annotation channel
    if ~isempty(iAnnotChans) && ismember(i, iAnnotChans)
        ChannelMat.Channel(i).Type = 'EDF';
        ChannelMat.Channel(i).Name = 'Annotations';
    elseif ~isempty(iStatusChan) && (i == iStatusChan)
        ChannelMat.Channel(i).Type = 'BDF';
        ChannelMat.Channel(i).Name = 'Status';
    % Regular channels
    else
        % If there is a pair name/type already detected
        if ~isempty(SplitName{i}) && ~isempty(SplitType{i})
            ChannelMat.Channel(i).Name = SplitName{i};
            ChannelMat.Channel(i).Type = SplitType{i};
        else
            % Channel name
            ChannelMat.Channel(i).Name = hdr.signal(i).label(hdr.signal(i).label ~= ' ');
            % Channel type
            if ~isempty(hdr.signal(i).type)
                if (length(hdr.signal(i).type) == 3)
                    ChannelMat.Channel(i).Type = hdr.signal(i).type(hdr.signal(i).type ~= ' ');
                elseif isequal(hdr.signal(i).type, 'Active Electrode')
                    ChannelMat.Channel(i).Type = 'EEG';
                else
                    ChannelMat.Channel(i).Type = 'Misc';
                end
            else
                ChannelMat.Channel(i).Type = 'EEG';
            end
        end
        % Remove the '-Ref' tag
        ChannelMat.Channel(i).Name = strrep(ChannelMat.Channel(i).Name, '-Ref', '');
    end
    ChannelMat.Channel(i).Loc     = [0; 0; 0];
    ChannelMat.Channel(i).Orient  = [];
    ChannelMat.Channel(i).Weight  = 1;
    % ChannelMat.Channel(i).Comment = hdr.signal(i).type;
end
% If there are only "Misc" and no "EEG" channels: rename to "EEG"
iMisc = find(strcmpi({ChannelMat.Channel.Type}, 'Misc'));
iEeg  = find(strcmpi({ChannelMat.Channel.Type}, 'EEG'));
if ~isempty(iMisc) && isempty(iEeg)
    [ChannelMat.Channel(iMisc).Type] = deal('EEG');
end


%% ===== READ EDF ANNOTATION CHANNEL =====
if ~isempty(iEvtChans) % && ~isequal(ImportOptions.EventsMode, 'ignore')
    % Set reading options
    ImportOptions.ImportMode = 'Time';
    ImportOptions.UseSsp     = 0;
    ImportOptions.UseCtfComp = 0;
    % Read EDF annotations
    if strcmpi(sFile.format, 'EEG-EDF')
        evtList = {};
        % Process separately the multiple annotation channels
        for ichan = 1:length(iEvtChans)
            % Read annotation channel epoch by epoch
            for irec = 1:hdr.nrec
                % Sample indices for the current epoch (=record)
                SampleBounds = [irec-1,irec] * sFile.header.signal(iEvtChans(ichan)).nsamples - [0,1];
                % Read record
                F = char(in_fread(sFile, ChannelMat, 1, SampleBounds, iEvtChans(ichan), ImportOptions));
                % Split after removing the 0 values
                Fsplit = str_split(F(F~=0), 20);
                if isempty(Fsplit)
                    continue;
                end
                % Get first time stamp
                if (irec == 1)
                    t0 = str2double(char(Fsplit{1}));
                end
                % If there is an initial time: 3 values (ex: "+44.00000+44.47200Event1)
                if (mod(length(Fsplit),2) == 1) && (length(Fsplit) >= 3)
                    iStart = 2;
                % If there is no initial time: 2 values (ex: "+44.00000Epoch1)
                elseif (mod(length(Fsplit),2) == 0)
                    iStart = 1;
                else
                    continue;
                end
                % If there is information on this channel
                for iAnnot = iStart:2:length(Fsplit)
                    % If there are no 2 values, skip
                    if (iAnnot == length(Fsplit))
                        break;
                    end
                    % Split time in onset/duration
                    t_dur = str_split(Fsplit{iAnnot}, 21);
                    % Get time and label
                    t = str2double(t_dur{1});
                    label = Fsplit{iAnnot+1};
                    if (length(t_dur) > 1)
                        duration = str2double(t_dur{2});
                    else
                        duration = 0;
                    end
                    if isempty(t) || isnan(t) || isempty(label) || (~isempty(duration) && isnan(duration))
                        continue;
                    end
                    % Add to list of read events
                    evtList(end+1,:) = {label, (t-t0) + [0;duration]};
                end
            end
        end
        
        % If there are events: create a create an events structure
        if ~isempty(evtList)
            % Initialize events list
            sFile.events = repmat(db_template('event'), 0);
            % Events list
            [uniqueEvt, iUnique] = unique(evtList(:,1));
            uniqueEvt = evtList(sort(iUnique),1);
            % Build events list
            for iEvt = 1:length(uniqueEvt)
                % Find all the occurrences of this event
                iOcc = find(strcmpi(uniqueEvt{iEvt}, evtList(:,1)));
                % Concatenate all times
                t = [evtList{iOcc,2}];
                % If second row is equal to the first one (no extended events): delete it
                if all(t(1,:) == t(2,:))
                    t = t(1,:);
                end
                % Set event
                sFile.events(iEvt).label   = uniqueEvt{iEvt};
                sFile.events(iEvt).times   = t;
                sFile.events(iEvt).samples = round(t .* sFile.prop.sfreq);
                sFile.events(iEvt).epochs  = 1 + 0*t(1,:);
                sFile.events(iEvt).select  = 1;
            end
        end
        
    % BDF Status line
    elseif strcmpi(sFile.format, 'EEG-BDF')
        % Ask how to read the events
        events = process_evt_read('Compute', sFile, ChannelMat, ChannelMat.Channel(iEvtChans).Name, ImportOptions.EventsTrackMode);
        if isequal(events, -1)
            sFile = [];
            ChannelMat = [];
            return;
        end
        % Report the events in the file structure
        sFile.events = events;
        % Remove the 'Status: ' string in front of the events
        for i = 1:length(sFile.events)
            sFile.events(i).label = strrep(sFile.events(i).label, 'Status: ', '');
        end
        % Group events by time
        % sFile.events = process_evt_grouptime('Compute', sFile.events);
    end
end

    
    

