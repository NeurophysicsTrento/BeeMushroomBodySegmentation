
% NOTE: 

% THIS SCRIPT USES OTSU THRESHOLDING TO IDENTIFY REGIONS WHERE THERE ARE MGs.

% Due to parallel computing the length of filevector needs to match the 
% number of active workers (4 on cimec cluster), with different files. 
% Otherwise the results get overwritten with zeros. The zero-padding
% is done to perform case handling if no MGs are found in a file aka worker
% has a file. . 

clear all,close all    % RUNTIME: 150s each image

%% PARAMETERS
% choose the name for the trial 
trial_name = 'A1_coloured'; 

% Thresholding and region properties
pixelsize=0.1; % pixel size in micron   
d2 = 4; % minimal allowed distacne between MGs in px
th = 90; % number of thresholds
minl = 0; % min intensity level
maxl = 0.23; % max intensityl level

% MG volume limits in voxel
% according to old code
volmin = 3; 
volmax = 5000;

% voxel dimension in um
% those values from paper
x_size = 0.1; 
y_size = 0.1; 
z_size = 0.1;

%% CHOOSE HERE THE PATHS
folderpath = '/mnt/storage/tier1/albhaa/haaalb001a1p/Data/Amelie/LTMstructuralPlasticity/MATLAB segmentation/'; % This is the home directory

datpath=fullfile(folderpath, 'Matlab Analysis/twophoton'); % Data is here
disp(datpath)

analyze_all_images = 0; % SET IT TO "1" TO ANALYZE ALL THE IMAGES IN THE FOLDER "Tiff images",
% NB09 couldn't be read
filevector = {'A1'};
%{'NB01', 'NB02', 'NB03', 'NB04', 'NB05', 'NB06', 'NB07', 'NB08', 'NB010'}; %filevector={'A1' 'A2' 'A3' 'A4' 'A5'}; % example

if analyze_all_images==1
    imagelist=dir(fullfile(datpath, 'Tiff images/*_image.tif')); % list of the files in "Tiff images" ending with "_image.tif"
    masklist=dir(fullfile(datpath, 'LipMask/*_LipMask.tif'));    % list of the files in "LipMask" ending with "_LipMask.tif"
    for im=1:length(imagelist)
        filevector{1,im} = imagelist(im).name(1:end-10); % put in "filevector" the image names (e.g. 'A1', 'Control1', 'NB07'...)
    end
end

% Folder to store resulting Excel files of all properties
resultsfolder = fullfile('/home/amelieluise.fehrmann/twophoton', ['Results_2P_MG_' trial_name]); 
if ~exist(resultsfolder, 'dir')  
   mkdir(resultsfolder) % creates the folder where results will be stored
end

% Write parameters into a file
% Define parameter names and values
paramNames = {'pixelsize', 'minl', 'maxl', 'th', 'd2', 'volmin', 'volmax', 'x_size', 'y_size', 'z_size'};
paramValues = [pixelsize, minl, maxl, th, d2, volmin, volmax, x_size, y_size, z_size];

% Define comments (units)
paramComments = { 'um/px', '', '', '', 'px', 'voxel', 'voxel', 'um', 'um', 'um'};

% Convert to table
paramTable = table(paramNames', paramValues', paramComments', 'VariableNames', {'Parameter', 'Value', 'Units'});

% Display the table
disp(paramTable);

% Save as CSV file
writetable(paramTable, fullfile(resultsfolder, 'parameters.csv'));

disp('Parameter table saved as parameters.csv');


%% Create tables and file names to gather data in the end
% create final table to gather data
numFiles = length(filevector);
final_table_11 = table();
final_table_22 = table();
final_table_33 = table();
final_table_44 = table();
final_table_55 = table();

% Initialize cell arrays for local results of individual workers
local_table_11 = {};
local_table_22 = {};
local_table_33 = {};
local_table_44 = {};
local_table_55 = {};

file_vol = [resultsfolder '/Results_vol_' filevector{1} '-' filevector{end} '_' trial_name '_final.csv'];  
file_ratio = [resultsfolder '/Results_aspectratio_' filevector{1} '-' filevector{end} '_' trial_name '_final.csv'];  
file_axes = [resultsfolder '/Results_axes_' filevector{1} '-' filevector{end} '_' trial_name '_final.csv'];  
file_dist = [resultsfolder '/Results_dist_' filevector{1} '-' filevector{end} '_' trial_name '_final.csv']; 
file_lipvol = [resultsfolder '/Results_lipvol_' filevector{1} '-' filevector{end} '_' trial_name '_final.csv'];  

% Start a parallel pool with 4 workers 
%parpool(4);
disp(numFiles)

%% Parallel working
% Split the list of files among workers
spmd
    % Create table for individual mask properties per file. Each
    % worker has a copy.
    table_11 = table();
    table_22 = table();
    table_33 = table();
    table_44 = table();
    table_55 = table();

    % Determine the number of files each worker will handle
    numWorkers = numlabs; % Total number of worker

    workerID = labindex;
    disp(['Worker ID: ', num2str(workerID)]);

    spmdIndex = labindex; % Index of the current worker
    filesPerWorker = ceil(numFiles / numWorkers);
    startIdx = (spmdIndex - 1) * filesPerWorker + 1;
    endIdx = min(spmdIndex * filesPerWorker, numFiles);

    %% Process the assigned files
    for i = startIdx:endIdx
        
        % Display the current file number (for debugging)
        disp(['Processing file ', num2str(i)]);
        
        tstart1 = tic;
        tstart0 = tic;

        % Get the current file
        rawfilename=[filevector{i},'_image.tif']; %3D image
        lipfilename=[filevector{i},'_LipMask.tif']; %ROI mask
        currentFile = [datpath '/Tiff images/' rawfilename];

        % Get file info
        fileinfo = imfinfo(currentFile);
        width = fileinfo(1).Width;
        height = fileinfo(1).Height;
        framenum_og = numel(fileinfo);

        % Load data
        lip = zeros(height, width, framenum_og, 'uint16');
        rawdata = zeros(height, width, framenum_og, 'uint16');
        for frame = 1:framenum_og
            rawdata(:,:,frame) = imread(currentFile, frame);
            lip(:,:,frame) = imread([datpath '/LipMask/' lipfilename], frame);
        end
        
        % Process the raw data
        data=rawdata.*uint16(lip);
        
        % Calculate lip volume 
        lipvolume=sum(lip,'all')*pixelsize^3;

        % convert volmin, volmax from um^3 into correct voxel number if not
        % already given in voxel
        voxel_size = x_size * y_size * z_size;
        volmin_1 = volmin / 1; 
        volmax_1 = volmax / 1; 

        %% OTSU Multithresholding 
        % MGs accross different thresholds are identified
        [MGtable, bw] = otsu_multithresholding(data, th, minl, maxl, volmin_1, volmax_1);

        %% Region Segmentation
        % Found MGs are invesitgated with the distance criterium. If two
        % MGs are closer than d2 and incorparated in each other this is 
        % considered an overlap.
        MGtable = regions(MGtable, th, d2);

        % Summarize data
        voldat = MGtable.Volume;
        centdat= MGtable.Centroid; % Working copy of centroid coordinates
        axdat = MGtable.PrincipalAxisLength;
        idxdat = MGtable.VoxelIdxList;
        thdat = MGtable.Thresh;
    
        %% Cluster Count
        % For the found overlaps, data from the bigger region is taken, 
        % positions are averaged. 
        [pos1, vol1, axe1, idx1, th1] = cluster_count(MGtable, centdat, voldat, axdat, idxdat, thdat);

        %% Save colour coded regions

        % create folder
        colouredoverlaycart=fullfile(resultsfolder, '/Coloured_regions/', filevector{i});
        if ~exist(colouredoverlaycart, 'dir') % creates results folder
            mkdir(colouredoverlaycart)
        end
           
        disp("This is proper mask name")
        disp(filevector{i})
        
        if i==1

            disp("hi")
            %reduce number of plotted frames
            binned_framenum = 1;

            window_data = data;

            file_n=[colouredoverlaycart '/composite_region_' filevector{i}]; % nome del file che creo
                    
            % create matrix with linear indexing of regions
            M = zeros(size(window_data));
            % iterate over regions
            for j = 1:size(pos1, 1) 
               M(idx1{j}) = j;
            end
    
            % iterate over indices of regions
            % Overlay the mask onto the original image
            window_data = uint8(window_data);
            overlay_region = zeros(size(window_data, 1), size(window_data, 2), 3, binned_framenum, 'uint8'); % 3 channels: red, green, blue
            bw=uint8(bw); % reconvert logical into uint16 
            colours = lines(size(pos1, 1));
    
            init = zeros(size(window_data));
            for fr = 1:binned_framenum
                init([1,1,fr]) = fr;
            end
    
            % iterate over regions
            for frame = 1:binned_framenum
                dot = init == frame;
                % initialize 4D overlay for every frame
                %overlay_region(:,:,1,frame) = window_data(:,:,frame);
                %overlay_region(:,:,2,frame) = window_data(:,:,frame);
                %overlay_region(:,:,3,frame) = window_data(:,:,frame);
                %overlay_region(:,:,:,frame) = imoverlay(window_data(:,:,frame), window_data(:,:,frame), [0 0 0]); 
                overlay_region(:,:,:,frame) = repmat(window_data(:,:,frame), [1, 1, 3]); % Create 3D overlay base for current frame
 
                % iterate over frames
                for k = 1:size(pos1, 1)
                    % update overlay for every region with another colour 
                    % Get the region mask for the current region and frame
                    region_mask = M == k;
                    % Overlay the region mask onto the original image + total mask
                    % Change colour per region
                    %{
                    if size(idx1{k}, 1) >= big 
                        overlay_region(:,:,:,frame) = imoverlay(overlay_region(:,:,:,frame), region_mask(:,:,frame), [0.5 0.5 0.5]);    
                    else
                        overlay_region(:,:,:,frame) = imoverlay(overlay_region(:,:,:,frame), region_mask(:,:,frame), colours(k,:));    
    
                    end
                    %}
                    overlay_region(:,:,:,frame) = imoverlay(overlay_region(:,:,:,frame), region_mask(:,:,frame), colours(k,:));    
                    % ensure tif campatibility
                    overlay_region = im2uint8(overlay_region);
                end   
            end
    
            % Create a multi-page TIFF file
            tifformat_2 = overlay_region;
            %tifformat = reshape(overlay, size(overlay, 1), size(overlay, 2), 3, []);
            % overlay is already 4D array, all good
            %tifformat= reshape(overlay, size(overlay, 1), size(overlay, 2), 1, 3, size(overlay, 3));
            % Write 3D tiff
            %s=whos('tifformat_2'); %size bigger than 32byte?
            % for bypassing whos (with s.bytes) in parallel context:
            % Approximate size calculation
            bytes_per_pixel = 2; % Assuming 16-bit depth
            estimated_size_bytes = numel(tifformat_2) * bytes_per_pixel;
            if estimated_size_bytes> 2^32 - 1
               tfile = Tiff(file_n, 'w8'); % Big Tiff file
            else
               tfile = Tiff(file_n, 'w');
            end
    
            % write composite to TIF
            tagstruct.ImageLength = size(overlay_region, 1);
            tagstruct.ImageWidth = size(overlay_region, 2);
            tagstruct.Photometric = Tiff.Photometric.RGB;
            tagstruct.BitsPerSample = 8;
            tagstruct.SamplesPerPixel = 3; % 3 channels red, green, blue
            tagstruct.PlanarConfiguration = Tiff.PlanarConfiguration.Chunky;
            for frame=1:binned_framenum
                tfile.setTag(tagstruct);
                tfile.write(overlay_region(:,:,:,frame));
                if frame ~= binned_framenum
                   tfile.writeDirectory(); % move to next page
                end
            end
            % Close the TIFF file
            tfile.close();
            
    
            tend=toc(tstart1);
    
            fprintf('Overlay data and coloured regions saved as TIF file in: %.1f s.\n',tend);
            DAT=tend;
            
        end  
    
    
        %% Calc Distances 
        tstart3 = tic;
        % calculate pairwise distances between the MG centroids
        distances = pdist(pos1, 'euclidean');
       
        %for l=numel(distances)
        %    formatted_dist{l} = sprintf('%.4f', distances(l));
        %end

        tend3 = toc(tstart3);
        fprintf('Distances calculated for file %s in: %.1f s.\n', filevector{i}, tend3);

        %% Unit Conversion       
        vol1 = vol1 .* voxel_size;
        axe1 = axe1 .* [x_size y_size z_size];
        distances = distances' .* nthroot(voxel_size, 3);

        %% Calc Aspect Ratio
        ratio = zeros(numel(vol1), 1);
        for l=1:numel(vol1)    
            if axe1(l,1) ~=0 
                ratio(l) = max(axe1(l,:)) ./ min(axe1(l,:));
            else
                ratio(l) = 0;
            end
        end
        

        %% Save Data about Masks of one File
        % write vol in csv
        vol_name = [resultsfolder '/Results_STED_Mask_vol_' filevector{startIdx} '-' filevector{endIdx} '_' trial_name '_worker' num2str(workerID) '.csv'];  
        header_11 = sprintf('Volume_um3_%s', filevector{i});
        table_11_new = table(vol1, 'VariableNames', {header_11});
        table_11 = save_table(table_11_new, table_11, vol_name, i, startIdx);
        
        % save aspect ratio as csv
        ratio_name = [resultsfolder '/Results_STED_Mask_aspectratio_' filevector{startIdx} '-' filevector{endIdx} '_' trial_name '_worker' num2str(workerID) '.csv'];   
        header_22 = sprintf('Aspect_ratio_vx_%s', filevector{i});
        table_22_new = table(ratio, 'VariableNames', {header_22});
        table_22 = save_table(table_22_new, table_22, ratio_name, i, startIdx);
        
        %{
        axes_name = [resultsfolder '/Results_STED_Mask_axes_' filevector{startIdx} '-' filevector{endIdx} '_' trial_name '_worker' num2str(workerID) '.csv'];   
        header_33 = {sprintf('Xaxis_um_%s', filevector{i}), sprintf('Yaxis_um_%s', filevector{i}), sprintf('Zaxis_um_%s', filevector{i})};
        table_33_new = array2table(axe1, 'VariableNames', {header_33});
        table_33 = save_table(table_33_new, table_33, axes_name, i, startIdx);
        %}
        
        dist_name = [resultsfolder '/Results_STED_Mask_dist_' filevector{startIdx} '-' filevector{endIdx} '_' trial_name '_worker' num2str(workerID) '.csv'];   
        header_44 = sprintf('dist_um_%s', filevector{i});
        table_44_new = table(distances, 'VariableNames', {header_44});
        table_44 = save_table(table_44_new, table_44, dist_name, i, startIdx);

        lipvol_name = [resultsfolder '/Results_STED_Mask_lipvol_' filevector{startIdx} '-' filevector{endIdx} '_' trial_name '_worker' num2str(workerID) '.csv'];   
        header_55 = sprintf('lipvol_um3_%s', filevector{i});
        table_55_new = table(lipvolume, 'VariableNames', {header_55});
        table_55 = save_table(table_55_new, table_55, lipvol_name, i, startIdx);

        tend=toc(tstart1);

        disp(filevector{i})
    
        fprintf('Data of masks %s saved in: %.1f s.\n', filevector{i}, tend-DAT);
        DAT=tend;  

    end

    % Store results in cell arrays per worker  
    local_table_11{end+1} = table_11;
    local_table_22{end+1} = table_22;
    local_table_33{end+1} = table_33;
    local_table_44{end+1} = table_44;
    local_table_55{end+1} = table_55;

    % Ensure "A" is printed if all else is okay
    disp('A');
 
end

%% Gather all the results from the differen workers in one big table per property
if labindex == 1
    % prevent overwriting
    final_table_11 = formatting_tables(local_table_11, file_vol);
    final_table_22 = formatting_tables(local_table_22, file_ratio);
    final_table_33 = formatting_tables(local_table_33, file_axes);
    final_table_44 = formatting_tables(local_table_44, file_dist);
    final_table_55 = formatting_tables(local_table_55, file_lipvol);
end



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function table_11 = save_table(table_11_new, table_11, file_name, f, startIdx)
    height_1 = size(table_11, 1);          % Rows of table_11
    height_1_new = size(table_11_new, 1);  % Rows of table_11_new

    % Padding table_11_new if its height is less than table_11
    if height_1_new < height_1
        padding = zeros(abs(height_1_new - height_1), width(table_11_new));
        disp(size(table_11_new))
        disp(size(array2table(padding, 'VariableNames', table_11_new.Properties.VariableNames)))
        table_11_new = [table_11_new; array2table(padding, 'VariableNames', table_11_new.Properties.VariableNames)];
    end

    % Padding table_11 if its height is less than table_11_new
    if height_1_new > height_1
        padding = zeros(abs(height_1_new - height_1), width(table_11));
        disp(size(table_11))
        disp(size(array2table(padding, 'VariableNames', table_11.Properties.VariableNames)))
        table_11 = [table_11; array2table(padding, 'VariableNames', table_11.Properties.VariableNames)];
    end

    % Debugging sizes before concatenation
    disp("SIZES");
    
    
    % If it's the first iteration, overwrite the file and save with headers
    if f + 1 - startIdx == 1
        table_11 = table_11_new;
        writetable(table_11, file_name, 'Delimiter', ',');
    else
        % Otherwise concatenate tables horizontally and save without headers
        disp(size(table_11))
        disp(size(table_11_new))
        table_11 = [table_11, table_11_new];
        writetable(table_11, file_name, 'Delimiter', ',');
    end

    disp("END OF WRITING")
end


function MGtable = regions(MGtable, th, d2)
       
    MGtable.ov=zeros(size(MGtable,1),1);  % 1 se fa overlap con soglia precedente(corpo maggiore)
    MGtable.rmv=zeros(size(MGtable,1),1); % if to be removed
    
    for i=size(MGtable,1):-1:1 % I scroll over the bodies found, from the higher threshold to the lower threshold
        if MGtable.Thresh(i)<th
            idxx=find(MGtable.Thresh>MGtable.Thresh(i) &...                % threshold greater than that considered (therefore smaller body)
                abs(MGtable.Centroid(:,1)- MGtable.Centroid(i,1))<d2 &...  % centroid distance < d2
                abs(MGtable.Centroid(:,2)- MGtable.Centroid(i,2))<d2 &...
                abs(MGtable.Centroid(:,3)- MGtable.Centroid(i,3))<d2&...
                sqrt((MGtable.Centroid(:,1)-MGtable.Centroid(i,1)).^2+(MGtable.Centroid(:,2)-MGtable.Centroid(i,2)).^2+(MGtable.Centroid(:,3)-MGtable.Centroid(i,3)).^2)<d2);
           % NOTE: idxx contains the index of the body (which overlaps) relating to MGtable
            if idxx>0 % if bodies with these characteristics exist
                idxlist=MGtable.VoxelIdxList(idxx); % I collect the pixel indices
                for j = 1:length(idxx) % for each of the bodies found
                    if sum(ismember(idxlist{j},MGtable.VoxelIdxList{i}))==length(idxlist{j}) % if all the voxels of the minor body "j" (major threshold) are contained in the major "i" (minor threshold)
                        MGtable.ov(i)=1; % I put ov = 1 to the body in question "i" e
                        MGtable.ov(idxx(j))=1; % to those involved in the overlap.
                        MGtable.rmv(idxx(j))=1; % I set rmv = 1 to the j (minor) bodies involved in the overlap: I REMOVE THEM BECAUSE THEY ARE SMALLER AND INCORPORATED IN THE "i" BODY
                    end
                end
            end
        end
        waitbar(i/length(i));
    end
        
    removed=sum(MGtable.rmv); % number of objects removed in the previous cycle.
    MGtable(MGtable.rmv==1,:)=[]; % I remove those with rmv=1 --> ov=1 remains in those that contained the removed ones.
    
    %NOTE: 1 threshold will be picked in the function cluster_count to
    %perform further volume and shape anaylsis
    
end

function [pos1, vol1, axe1, idx1, th1] = cluster_count(MGtable, centdat, voldat, axdat, idxdat, thdat)
% initialize to safe runtime

    estimated_clusters = sum(MGtable.ov);  % Example estimate
    pos1 = zeros(estimated_clusters, 3); % Initialize pos1 with zeros
    vol1 = zeros(estimated_clusters, 1); % Initialize vol1 with zeros
    axe1 = zeros(estimated_clusters, 3); % Initialize axe1 with zeros
    th1 = zeros(estimated_clusters, 1);   % Initialize th1 with zeros
    idx1 = cell(estimated_clusters, 1);   % Initialize idx1 as an empty cell array

    % pick one threshold: average
    m=0; % Cluster count
    for i=1:size(MGtable,1)
        if MGtable.ov(i)==1  % if there are objects that overlap with the object "i" (besides itself (ol=1))
            m=m+1; % Cluster count
            pos1(m,:)=centdat(i,:); % Average position of all overlaps
            vol1(m)=voldat(i); % Max volume of overlaps
            axe1(m,:)=axdat(i,:); % Max axes of all overlaps
            idx1{m}=idxdat{i}; %Indeces of all MG voxels
            th1(m)=thdat(i);
        end
        waitbar(i/length(i));
    end

    clear MGtable % clear to free memory
end

function [MGtable, bw] = otsu_multithresholding(nblurred, th, minl, maxl, volmin_1, volmax_1)
    % Do OTSU-multi-thresholding here
    MGdata = cell(th, 1);
    for thresh = 1:th
        level = minl + (thresh - 1) * (maxl - minl) / (th - 1);
        bw = imbinarize(nblurred, level);
        props = regionprops3(bw, 'Centroid', 'Volume', 'VoxelIdxList', 'PrincipalAxisLength', 'Orientation');
        MGdata{thresh} = props;
        MGdata{thresh}.Thresh(:) = thresh;
    end

    % Concatenate and filter MGdata
    MGtable = vertcat(MGdata{:});
    MGtable(MGtable.Volume > volmax_1, :) = [];
    MGtable(MGtable.Volume < volmin_1, :) = [];
end 

function final_table_33 = formatting_tables(local_table_33, file_count)
    
    if ~isempty(local_table_33) 
        
        % After parallel execution, gather data from the Composite
        local_table_33 = gather(local_table_33);  % Convert from Composite to cell array
        
        local_table_33 = local_table_33(:);  % flatten the array
            
        % Determine the maximum length of tables
        maxLength_3 = 0;
        maxWidth_3 = 0;
    
        % Unwrap nested cells and find maximum length for local_table_11
        for idxx = 1:length(local_table_33)
            % Unwrap if it is a cell containing a table
            disp(class(local_table_33))
            disp(size(local_table_33))
            while ~istable(local_table_33{idxx}) 
                local_table_33{idxx} = local_table_33{idxx}{1};
            end
    
            % Convert to table
            %local_table_33{idxx} = cell2table(local_table_33{idxx});
        
            % Update maximum length
            if size(local_table_33{idxx}, 1) > maxLength_3
                maxLength_3 = size(local_table_33{idxx}, 1);
            end
            if size(local_table_33{idxx}, 2) > maxWidth_3
                maxWidth_3 = size(local_table_33{idxx}, 2);
            end
        end
                
        % Pad the shorter tables for local_table_11
        for idx = 1:length(local_table_33)
            % Calculate padding needed
            % Handle empty tables
            % Columns
            if size(local_table_33{idx}, 1) == 0 || size(local_table_33{idx}, 2) == 1
                paddingCols = 1;
                % Generate new variable names for padding columns
                newVarNames = arrayfun(@(x) sprintf('CountVar_%d_%d', idx, x), ...
                                       1:paddingCols, 'UniformOutput', false);
                % Create padding table with new variable names
                padding = zeros(maxLength_3, paddingCols);
                paddingTable = array2table(padding, 'VariableNames', newVarNames);
                % vertical concatenation
                local_table_33{idx} = paddingTable;
            end 
            if size(local_table_33{idx}, 2) < maxWidth_3
                paddingCols = maxWidth_3 - size(local_table_33{idx}, 2);
                % Existing column names
                %existingVarNames = local_table_11{idx}.Properties.VariableNames;
                % Generate new variable names for padding columns
                newVarNames = arrayfun(@(x) sprintf('CountVar_%d_%d', idx, x), ...
                                       1:paddingCols, 'UniformOutput', false);
                % Create padding table with new variable names
                padding = zeros(size(local_table_33{idx}, 1), paddingCols);
                paddingTable = array2table(padding, 'VariableNames', newVarNames);
                % vertical concatenation
                local_table_33{idx} = [local_table_33{idx}, paddingTable];
            end
            % Rows    
            if size(local_table_33{idx}, 1) < maxLength_3
                paddingRows = maxLength_3 - size(local_table_33{idx}, 1);
                padding = zeros(paddingRows, size(local_table_33{idx}, 2));
                if numel(local_table_33{idx}{end, end}) ~= 1
                    arr = zeros(length(local_table_33{idx}{end, end}));
                    disp(size(arr))
                    padding = repmat(arr, paddingRows, 1); % repeat once per row
                end 
                paddingTable = array2table(padding, 'VariableNames', local_table_33{idx}.Properties.VariableNames);
                % horizontal concatenation
                local_table_33{idx} = [local_table_33{idx}; paddingTable];
            end
        end
    
        disp("I MADE IT OUT")
    
        % Combine all tables from cell arrays into single tables
        final_table_33 = horzcat(local_table_33{:});
    
        % Save the overall table 
        writetable(final_table_33, file_count, 'Delimiter', ',');
    end

end
    
