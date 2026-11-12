
% NOTE: 
% This code is build to investigates the old STED data and the new data of 
% 2024 that ends with STAR RED STED.ome.tiff. On can switch between the old
% and new data adjusting the parts of the code where "STED 2024" or "STED
% old" is commented.

% THIS SCRIPT USES OTSU THRESHOLDING TO IDENTIFY REGIONS WHERE THERE ARE MGs.
% IT CREATES A MASK FOR EACH REGION, AND SAVES IT IN THE FOLDER "OTSU_MASKS"
% AFTER MULTIPLIYNG IT BY THE ORIGINAL IMAGE.

% Due to parallel computing the length of filevector needs to match the 
% number active of workers (4 on cimec cluster), with different files. 
% Otherwise the results get overwritten with zeros. The zero-padding
% is done to perform case handling if no MGs are found in a file aka worker
% has no file.

clear all,close all    % RUNTIME: 150s each image

%% PARAMETERS
% choose the name for the trial 
trial_name = 'STEDold_real'; 

% Thresholding and region properties
% NOTE: Those parameters were optimized in the previous scripts and given
% in voxel or pixel. They are used here but I figured that there was a
% slightly different unit conversion (by 1%) due to the interpolation 
% for blurring. Thus, the volmax is not exaclty 2 um^3 but 1.99 um^3.
pixelsize=10/400; % pixel size in micron   % could be nthroot(voxel_size, 3)
d = 9;
d2 = (5+d)*0.1/pixelsize; % Distance between the centers of two objects under which they are considered as being the same microglomerulus
th = 22; % number of thresholds
minl = 0.2; % min intensity level
maxl = 0.55; % max intensity level

ol = 2; % number of required overlapping regions 

% MG volume limits in voxel
volmin = 3;
volmax = 2/pixelsize^3;

% og voxel dimension in um (before resampling/post-processing/blurring)
x_size = 0.025; 
y_size = 0.025;
z_size = 0.3;

%% CHOOSE HERE THE PATHS

folderpath = '/mnt/storage/tier1/albhaa/haaalb001a1p/Data/Amelie/LTMstructuralPlasticity/MATLAB segmentation/Matlab Analysis/'; % for STED old '/mnt/storage/tier1/albhaa/haaalb001a1p/Data/Amelie/LTMstructuralPlasticity/MATLAB segmentation/Matlab Analysis/'; % STED 2024 '/home/amelieluise.fehrmann/STED/';    % This is the home directory

% Folder to store resulting Excel files of all properties
resultsfolder = fullfile('/home/amelieluise.fehrmann/STED/', ['Results_STED_MASKS_' trial_name]); 
if ~exist(resultsfolder, 'dir')  
   mkdir(resultsfolder) % creates the folder where results will be stored
end

% Folder to store OTSU-Masks
result_masks = fullfile('/home/amelieluise.fehrmann/STED/', ['OTSU_MASKS_'  trial_name]); 

% Write parameters into a file
% Define parameter names and values
paramNames = {'pixelsize', 'minl', 'maxl', 'th', 'd2', 'ol', 'volmin', 'volmax', 'x_size', 'y_size', 'z_size'};

paramValues = [pixelsize, minl, maxl, th, d2, ol, volmin, volmax, x_size, y_size, z_size];

% Define comments (units)
paramComments = { 'um/px', '', '', '', 'px', '', 'voxel', 'voxel', 'um', 'um', 'um'};

% Convert to table
paramTable = table(paramNames', paramValues', paramComments', 'VariableNames', {'Parameter', 'Value', 'Units'});

% Display the table
disp(paramTable);

% Save as CSV file
writetable(paramTable, fullfile(resultsfolder, 'parameters.csv'));

disp('Parameter table saved as parameters.csv');

% For STED 2024 we need a drift correction. To investigate this more easily, enter here the path to the file with the drifts.
driftPath = '/home/amelieluise.fehrmann/STED/Results_STED_MASKS_homoBackground/Results_STED_Mask_total_drift_ctr_A_04_external-imi_C_09_internal.csv'; 

datpath = dir(fullfile(folderpath, 'STED/Sted data/*.tif')); % STED old dir(fullfile(folderpath, 'STED/Sted data/*.tif')); % STED 2024 dir(fullfile(folderpath, 'STED_data2024_new_shift')); % thihs is where data lies to investigate
% STED 2024 dir(fullfile(folderpath, 'STED_data2024_new_shift/*/Sample*/drift_corrected_background_*')); 

analyze_all_images = 1; % SET IT TO "1" TO ANALYZE ALL THE IMAGES 
filevector_1= {}; %{'ctr_A_06_external','day0_08_external', 'imi_B_14_external'}; % Choose here the images to be analyzed like 'C1 1'

if analyze_all_images==1
    imagelist=datpath; % list of the files in "Tiff images" ending with "_image.tif"
    for im=1:length(imagelist)
        folderName = datpath(im).name;
        filevector_1{1, im} = folderName; % store the constructed filename in filevector
    end    
end 


%% Sort for imaes with correct drift if necesssary (structure for STED 2024)
filevector = {}; % Empty cell array
total_drift = []; % Empty array

% take only the raw data with low drift
%{
%opts = detectImportOptions(driftPath);
%drift = readtable(driftPath, opts);
%drift = readtable(driftPath, 'PreserveVariableNames', true);
%drift.Properties.VariableNames = matlab.lang.makeValidName(drift.Properties.VariableNames);
%headers_drift = drift.Properties.VariableNames;
%drift = readtable(driftPath, 'PreserveVariableNames', true);
%headers_drift = drift.Properties.VariableNames;
%disp(header_drift);
% Read the table with PreserveVariableNames option set to true
drift = readtable(driftPath, 'PreserveVariableNames', true);

% Display original column headers
originalHeaders = drift.Properties.VariableDescriptions;
disp('Original Headers:');
%disp(originalHeaders);

% Adjust variable names if necessary
drift.Properties.VariableNames = matlab.lang.makeValidName(drift.Properties.VariableNames);

% Display adjusted column headers
headers_drift = drift.Properties.VariableNames;
disp('Adjusted Headers:');
%disp(headers_drift);

for i=1:size(drift, 2)
    driftName = strtrim(headers_drift{1, i}); % remove potential leading and trailing whitespaces for comparising if-statement, keep spaces for data access
    %parts = strsplit(headers_drift{i}, '_');
    % Get the last part of the column name
    driftPart = driftName(10:end); 
        
    drift_x = table2array(drift(1,i));
    drift_y = table2array(drift(2,i));

    tot_drift(i) = sqrt(drift_x^2 + drift_y^2);
    
    for j=1:length(filevector_1)
       
        fileName = strtrim(filevector_1{1, j});

        % ensure compatibility
        driftPart = cellstr(driftPart);
        if tot_drift(i) > 20 
            if strcmpi(driftPart, fileName) 
                total_drift(1, j) = tot_drift(i);
                filevector{1, j} = fileName;
            end
        end
    end
end
%}

% if no drifft picking is done
filevector = filevector_1;

%% Load data
% STED old data Lyon
dirlist = datpath;

% for STED 2024 using this work around currently
% this is a temporary workaround for STED 2024, until the data set is
% correctl cleaned 
%{
cartlist = {};
samplelist = {};
dirlist = {};
for item=1:length(filevector)   
    folderName = num2str(filevector{item});

    % Skip '.' and '..' which are not actual directories
    if strcmp(folderName, '.') || strcmp(folderName, '..')
        continue;
    end
    % if the foldername ends with _external or _internal, add it to the
    % cartlist
    % if the foldername ends with _external or _internal, add it to the cartlist
    if endsWith(folderName, '_external') || endsWith(folderName, '_internal')
        % Construct the full path to the current folder
        folderPath = fullfile(datpath(item).folder, folderName);

        cartlist{end+1} = folderPath;

        % Construct the path pattern for Sample folders
        samplePattern = fullfile(folderPath, 'Sample*');

        % Get the list of Sample folders
        sampleFolders = dir(samplePattern);

        % Loop through each Sample folder and add its path to samplelist
        for i = 1:length(sampleFolders)
            samplelist{end+1} = fullfile(folderPath, sampleFolders(i).name);

            % Create file patterns
            pattern1 = fullfile(samplelist{end}, '*drift_corrected_background_* *STAR RED STED.ome.tiff');
            pattern2 = fullfile(samplelist{end}, '*drift_corrected_background_* *STAR RED STED.tif'); % Replace with your second pattern

            % Get the list of files matching the first pattern
            fileList1 = dir(pattern1);
            % Get the list of files matching the second pattern
            fileList2 = dir(pattern2);

            % Combine the results from both patterns
            fileList = [fileList1; fileList2];

            % Remove duplicate entries based on their full path
            [~, uniqueIdx] = unique({fileList.folder});
            uniqueFiles = fileList(uniqueIdx);

            % Add unique files to dirlist
            for k = 1:length(uniqueFiles)
                % Add the current file path to dirlist
                dirlist{end+1} = dir(fullfile(samplelist{end}, uniqueFiles(k).name));
            end 
        end
    end
end
%}


%% Create tables and file names to gather data in the end
% create final table to gather data
numFiles = length(dirlist);
final_table_11 = table();
final_table_22 = table();
final_table_33 = table();
final_table_44 = table();

% Initialize cell arrays for local results of individual workers
local_table_11 = {};
local_table_22 = {};
local_table_33 = {};
local_table_44 = {};

file_vol = [resultsfolder '/Results_STED_Mask_vol_' filevector{1} '-' filevector{end} '_' trial_name '_final.csv'];  
file_ratio = [resultsfolder '/Results_STED_Mask_aspectratio_' filevector{1} '-' filevector{end} '_' trial_name '_final.csv'];  
file_axes = [resultsfolder '/Results_STED_Mask_axes_' filevector{1} '-' filevector{end} '_' trial_name '_final.csv'];  
file_dist = [resultsfolder '/Results_STED_Mask_dist_' filevector{1} '-' filevector{end} '_' trial_name '_final.csv'];  


%% Parallel working
% Split the list of files among workers
spmd
    % Create table for individual mask properties per file. Each
    % worker has a copy. 
    table_11 = table();
    table_22 = table();
    table_33 = table();
    table_44 = table();

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

        % Get the current file (name matching)

        %{
        % for STED 2024
        currentFile = fullfile(dirlist{i}.folder, dirlist{i}.name);
        % Split the directory path by the file separator
        folders = strsplit(cartlist{i}, filesep);
        Name = folders{end};
        disp(Name)
        %}
       
        
        % for STED old  
        currentFile = fullfile(dirlist(i).folder, dirlist(i).name);
        File = dirlist(i).name;
        % Split the directory path by the file separator
        group_name = strsplit(File, '_');
        tokens = regexp(File, 'hires (\d+)', 'tokens');
        % Construct the desired folder name
        Name = [group_name{1} '_hires_' tokens{1}{1}];
        disp(Name) 
        

        % Get file info
        fileinfo = imfinfo(currentFile);
        width = fileinfo(1).Width;
        height = fileinfo(1).Height;
        framenum_og = numel(fileinfo);

        % Initialize raw data storage
        rawdata = zeros(height, width, framenum_og, 'uint16');
        for frame = 1:framenum_og
            rawdata(:,:,frame) = imread(currentFile, frame);
        end

        % Process the raw data
        window_data = uint16(rawdata);

        %% Pepare STED data for OTSU - thresholding (interpolation, filter, blurring...)
        % interpolation
        % in crt_A_08_internal is a different width, that's why I adjust
        % the samplingin Xq here
        % Define the grid based on the size of window_data (using a specific range for each dimension)
        % Get the size of the window data in each dimension
        x_points = size(window_data, 2);  % Number of points in X direction
        y_points = size(window_data, 1);  % Number of points in Y direction
        z_points = size(window_data, 3);  % Number of points in Z direction
        % Desired number of points for the grid
        target_points = max([x_points, y_points, z_points]); % 400

        % Compute the step size for each dimension
        x_step = (x_points - 1) / (target_points - 1);
        y_step = (y_points - 1) / (target_points - 1);
        z_step = (z_points - 1) / (target_points - 1);

        % Generate the ranges for each dimension (1 to max, with step size)
        X_range = 1:x_step:x_points;  % Range for X
        Y_range = 1:y_step:y_points;  % Range for Y
        Z_range = 1:z_step:z_points;  % Range for Z

        % Create the meshgrid using the calculated ranges
        %[Xq, Yq, Zq] = meshgrid(1:(size(window_data, 2)-1)/(size(window_data, 1)-1):size(window_data, 2), 1:size(window_data, 1), 1:(size(window_data, 3)-1)/(size(window_data, 1)-1):size(window_data, 3));
        [Xq, Yq, Zq] = meshgrid(X_range, Y_range, Z_range);

        data = interp3(double(window_data), Xq, Yq, Zq);
        % normalization
        ndata=data/max(data(:)); % normalize
        framenum=size(data,3);
                
        % Gero's DoG filter
        for j=1:framenum
            data_f_n(:,:,j)=imgaussfilt(ndata(:,:,j)*10,0.6)-imgaussfilt(ndata(:,:,j)*10,3)*0.75;   % Filtered data (Gero's Filter DoubleGaussian)
        end
       
        sigma=round(0.25/pixelsize);
        h = fspecial('gaussian',3*sigma,sigma);
           
        blurred = imfilter(data,h,'conv');

        nblurred = blurred/max(max(max(blurred))); % Blurred and Normalized image
        
        % in crt_A_08_internal is a different width, that's why I adjust
        % x here
        % convert voxels after interpolation into um^3
        voxel_size = (x_size * size(window_data, 2) / size(nblurred, 2)) * (y_size * size(window_data, 1) / size(nblurred, 1)) * (z_size * framenum_og / framenum); 

        % convert volmin, volmax from um^3 into correct voxel number after
        % interpolation if it is not already in voxels.
        % prevent overwriting volmin, volmax on each worker using *_1.
        
        %volmin_1 = volmin / voxel_size; 
        %volmax_1 = volmax / voxel_size; 
        volmin_1 = volmin;
        volmax_1 = volmax;

        disp("data preparation done")

        %% OTSU Multithresholding 
        % MGs accross different thresholds are identified
        MGtable = otsu_multithresholding(nblurred, th, minl, maxl, volmin_1, volmax_1);

        disp("otsu done")

        % Summarize data
        glos=MGtable; % Working copy of whole table
        voldat = MGtable.Volume;
        centdat= MGtable.Centroid; % Working copy of centroid coordinates
        axdat = MGtable.PrincipalAxisLength;
        idxdat = MGtable.VoxelIdxList;
        thdat = MGtable.Thresh;
        
        %% Identify overlapping MGs and deal with them 
        % If there are MGs with centroids closer than d2 this is
        % considered an overlap. If there are more than ol overlaps, the
        % data from the bigger MG is chosen and the positions are averaged.
        [pos1, vol1, axe1, idx1, th1] = regions_and_cluster_count(glos, d2, ol, voldat, centdat, axdat, idxdat, thdat);
        
        % test for overlap
        %{
        labels=zeros(size(window_data));
        ovmg=0;
        if ~isempty(vol1)
            for k=1:size(vol1,2)
                if sum(labels(idx1{k}))>0 %already labels in MG volume?
                ovmg=ovmg+1;
                end
                labels(idx1{k})=k;
            end
        end
        store that somewehre to look into MG distance optimization
        %}

        disp("regions done")
    
        
        %% Create and save OTSU masks
        if ~isempty(vol1)

            for k = 1:size(vol1, 1)
               
                tstart2 = tic;
                maschera = uint16(zeros(size(data)));
                maschera(idx1{k}) = 1;
                filtdata = uint16(rescale(data_f_n, 0, 65535));
              
                results = fullfile(result_masks, [Name '_XY-OTSU']);
                if ~exist(results, 'dir')
                    mkdir(results);
                end
                maskname_n = fullfile(results, sprintf('Mask_%d_d.tif', k));
    
                height = size(nblurred, 1);
                width = size(nblurred, 2);
                tifformat = reshape(maschera .* filtdata, height, width, 1, framenum);
    
                %s = whos('tifformat');
                % for bypassing whos (with s.bytes) in parallel context:
                % Approximate size calculation
                bytes_per_pixel = 2; % Assuming 16-bit depth
                estimated_size_bytes = numel(tifformat) * bytes_per_pixel;
                if estimated_size_bytes> 2^32 - 1
                    tfile = Tiff(maskname_n, 'w8');
                else
                    tfile = Tiff(maskname_n, 'w');
                end
    
                tagstruct.ImageWidth = width;
                tagstruct.ImageLength = height;
                tagstruct.PlanarConfiguration = Tiff.PlanarConfiguration.Chunky;
                tagstruct.Photometric = Tiff.Photometric.MinIsBlack;
                tagstruct.BitsPerSample = 16;
                tagstruct.SamplesPerPixel = 1; % Assuming a grayscale image
    
                for f = 1:framenum
                    tfile.setTag(tagstruct);
                    tfile.write(tifformat(:, :, :, f));
                    if f ~= framenum
                        tfile.writeDirectory();
                    end
                end
                
                tfile.close();
    
                tend2 = toc(tstart2);
                fprintf('Mask %d created in: %.1f s.\n', k, tend2);
            end 
            
    
            tend0 = toc(tstart0);
            fprintf('Masks created for file %s in: %.1f s.\n', Name, tend0);
        
            %% Calc Distances 
            tstart3 = tic;
            % calculate the pairwise distances between the MGs
            distances = pdist(pos1, 'euclidean');
           
            %for l=numel(distances)
            %    formatted_dist{l} = sprintf('%.4f', distances(l));
            %end
    
            tend3 = toc(tstart3);
            fprintf('Distances calculated for file %s in: %.1f s.\n', Name, tend3);
    
            %% Unit Conversion
            % original sizes in um
            % in crt_A_08_internal is a different width, that's why I adjust
            % x here
            % convert from voxels after interpolation into um^3
            % altered number of slices due to interpolation in order to get similiar sampling as in x, y:
            framenum_og = numel(fileinfo); %33
            framenum = size(data,3); %400
    
            x_size_1 = x_size * size(window_data, 2) / size(nblurred, 2);
            y_size_1 = y_size * size(window_data, 1) / size(nblurred, 1);
            z_size_1 = z_size * framenum_og / framenum;
           
            voxel_size = x_size_1 * y_size_1 * z_size_1;
    
            vol1 = vol1 .* voxel_size;
            axe1 = axe1 .* [x_size_1 y_size_1 z_size_1];
            distances = distances' .* nthroot(voxel_size, 3);
    
            %% calc Aspect Ratio
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
            vol_name = [resultsfolder '/Results_STED_Mask_vol_' filevector{1} '-' filevector{end} '_' trial_name num2str(workerID) '.csv'];  
            header_11 = sprintf('Volume_um3_%s', Name);
            table_11_new = table(vol1, 'VariableNames', {header_11});
            table_11 = save_table(table_11_new, table_11, vol_name, i, startIdx);
            
            % save aspect ratio as csv
            ratio_name = [resultsfolder '/Results_STED_Mask_aspectratio_' filevector{1} '-' filevector{end} '_' trial_name num2str(workerID) '.csv'];   
            header_22 = sprintf('Aspect_ratio_vx_%s', Name);
            table_22_new = table(ratio, 'VariableNames', {header_22});
            table_22 = save_table(table_22_new, table_22, ratio_name, i, startIdx);
            %{
            axes_name = [resultsfolder '/Results_STED_Mask_axes_' filevector{1} '-' filevector{end} '_' trial_name num2str(workerID) '.csv'];   
            header_33 = {sprintf('Xaxis_um_%s', Name), sprintf('Yaxis_um_%s', Name), sprintf('Zaxis_um_%s', Name)};
            table_33_new = array2table(axe1, 'VariableNames', {header_33});
            table_33 = save_table(table_33_new, table_33, axes_name, i, startIdx);
            %}
            dist_name = [resultsfolder '/Results_STED_Mask_dist_' filevector{1} '-' filevector{end} '_' trial_name num2str(workerID) '.csv'];   
            header_44 = sprintf('dist_um_%s', Name);
            table_44_new = table(distances, 'VariableNames', {header_44});
            table_44 = save_table(table_44_new, table_44, dist_name, i, startIdx);
            
            tend=toc(tstart1);
    
            disp(Name)
        
            fprintf('Data of masks %s saved in: %.1f s.\n', Name, tend);
            DAT=tend;  
    
            if framenum_og ~= 33
                fprintf('ATTENTION: Framenum different in %s: %.1f s.\n', Name, framenum_og);
            end 
        end 
    end

    % Store results in cell arrays for each worker   
    local_table_11{end+1} = table_11;
    local_table_22{end+1} = table_22;
    local_table_33{end+1} = table_33;
    local_table_44{end+1} = table_44;

    % Ensure "A" is printed if all else is okay
    disp('A');
    
end

%% Gather the results from each worker in one big table per property
if labindex == 1
% prevent overwriting
final_table_11 = formatting_tables(local_table_11, file_vol);
final_table_22 = formatting_tables(local_table_22, file_ratio);
final_table_33 = formatting_tables(local_table_33, file_axes);
final_table_44 = formatting_tables(local_table_44, file_dist);
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
end


function [pos1, vol1, axe1, idx1, th1] = regions_and_cluster_count(glos, d2, ol, voldat, centdat, axdat, idxdat, thdat)
   % Initialize outputs as empty
    pos1 = [];
    vol1 = [];
    axe1 = [];
    idx1 = {};
    th1 = [];

    ED = single(pdist(centdat)); % Pairwise distance
    sqED = squareform(ED); % In matrix form
    same = sqED < d2; % distance smaller than distlimit creates overlap matrix
    overl= sum(same,2); % Column vector of number of overlaps
    m=0; % Cluster count
    while ~isempty(overl) % loop as long as there are overlapping clusters
        %position of all representation equal to first row of same matrix
        [~,id]=sort(same(1,:),'descend'); % id positions of overlap, val is 1 for overlap
            if overl(1)> ol
                %only if there are more than 1 occurences
                %collect data for the cluster of equals
                m=m+1; % Cluster count
                pos1(m,:)=mean(centdat(id(1:overl(1)),:),1); % Average position of all overlaps
                vol1(m, 1)=max(voldat(id(1:overl(1)))); % Max volume of overlaps
                axe1(m,:)=max(axdat(id(1:overl(1)),:),[],1); % Max axes of all overlaps
                idx1{m}=idxdat{id(1)}; %Indeces of all MG voxels
                th1(m, 1)=mean(thdat(id(1:overl(1))));
            end
        glos(id(1:overl(1)),:)=[]; % Remove treated cluster from whole database
        centdat(id(1:overl(1)),:)=[]; % Remove treated cluster from centroid data
        voldat(id(1:overl(1)))=[]; % Remove treated cluster from volume data
        thdat(id(1:overl(1)))=[];
        axdat(id(1:overl(1)),:)=[]; % Remove treated cluster from axes data
        idxdat(id(1:overl(1)),:)=[]; % Remove treated cluster from index data
        same(id(1:overl(1)),:)=[]; % Remove treated cluster from overlap matix lines
        same(:,id(1:overl(1)))=[]; % Remove treated cluster folrom overlap matix columns
        overl= sum(same,2); % Recalculculate remaining overlaps
    end
    
end

function MGtable = otsu_multithresholding(nblurred, th, minl, maxl, volmin_1, volmax_1)
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
                disp(size(local_table_33{idx}))
                paddingTable = array2table(padding, 'VariableNames', newVarNames);
                % vertical concatenation
                local_table_33{idx} = paddingTable;
            end 
            % Cols
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
                    arr = zeros(numel(local_table_33{idx}{end, end}));
                    disp(size(arr))
                    padding = repmat(arr, paddingRows, 1); % repeat once per row
                end 
                paddingTable = array2table(padding, 'VariableNames', local_table_33{idx}.Properties.VariableNames);
                % horizontal concatenation
                disp(size(local_table_33{idx}))
                disp(size(paddingTable))
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
