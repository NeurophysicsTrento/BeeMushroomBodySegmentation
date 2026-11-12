
% Code for SPU segmentation on OTSU masks
% switch between "STED old" and "STED 2024" whith adjusting the
% corresponding code parts (commented "STED old / 2024")

% Clear workspace and close all figures     
clear all
close all

%% Specify paths
% name of new analysis name must match otsu mask naming
trial_name = 'STED2024_real_d2_0.4um_volmax5um3';
% overall folder 
folderpath = '/home/amelieluise.fehrmann/';
% masks to be investigated
datpath=fullfile(folderpath, 'STED', ['OTSU_MASKS_' trial_name]); 

% Path to corresponding raw STED data
rawdata_path = dir(fullfile('/home/amelieluise.fehrmann/STED/STED_data2024_new_shift/*/Sample*/drift_corrected_background_*'));
% STED old dir(fullfile('/mnt/storage/tier1/albhaa/haaalb001a1p/Data/Amelie/LTMstructuralPlasticity/MATLAB segmentation/Matlab Analysis/', 'STED/Sted data/*.tif'));  
% STED 2024 dir(fullfile('/home/amelieluise.fehrmann/STED/STED_data2024_new_shift/*/Sample*/drift_corrected_background_*')); % STED old dir(fullfile('/mnt/storage/tier1/albhaa/haaalb001a1p/Data/Amelie/LTMstructuralPlasticity/MATLAB segmentation/Matlab Analysis/', 'STED/Sted data/*.tif'));
 
analyze_all_images = 1; % SET IT TO "1" TO ANALYZE ALL THE IMAGES 
filevector={}; %{'imi_C_08_external', 'imi_B_16_external', 'imi_B_16_internal','imi_B_17_external', 'imi_B_17_internal'}; %{'imi_B_16_external', 'imi_B_16_internal','imi_B_17_external', 'imi_B_17_internal'}; % Choose here the images to be analyzed like 'C1 1'

if analyze_all_images==1
    imagelist=dir(fullfile(datpath, '*_XY-OTSU*')); % list of the files 
    disp(imagelist)
    for im=1:length(imagelist)
        folderName = imagelist(im).name;
        filevector{1, im} = folderName(1:end-8); % store the constructed filename in filevector
    end    
end


%% Initialize

% set parameters
pixelsize=10/400; % voxel size in micron
minl=0.05; % min intensity level
maxl=0.8; % max intensity level
th=70; % number of thresholds
d2=2; % min distance between two different SPUs
compression_factor=1;

% maximal volumina in voxel after post-processing
volmin=35; 
volmax=0.02/pixelsize^3; 

% og voxel dimension in um (before resampling, post-processing)
x_size = 0.025; 
y_size = 0.025; 
z_size = 0.3;

resultsfolder = fullfile('/home/amelieluise.fehrmann/STED/SPU_Count', trial_name);   
if ~exist(resultsfolder, 'dir')  
   mkdir(resultsfolder) % creates the folder where results will be stored
end

% create resultfolder for volumes
result_volume=fullfile(resultsfolder, 'VOLUME') ;
if ~exist(result_volume, 'dir')  
   mkdir(result_volume) % creates the folder where the summary of the results will be stored
end
% create resultfolder for counts
result_count=fullfile(resultsfolder, 'COUNT') ;
if ~exist(result_count, 'dir')  
   mkdir(result_count) % creates the folder where the summary of the results will be stored
end
% create resultfolder for aspect ratio
result_aspect_ratio=fullfile(resultsfolder, 'ASPECT RATIO') ;
if ~exist(result_aspect_ratio, 'dir')  
   mkdir(result_aspect_ratio) % creates the folder where the summary of the results will be stored
end
% create resultfolder for correlation coefficient vr
result_axe=fullfile(resultsfolder, 'AXES') ;
if ~exist(result_axe, 'dir')  
   mkdir(result_axe) % creates the folder where the summary of the results will be stored
end

% Write parameters into a file
% Define parameter names and values
paramNames = {'pixelsize', 'minl', 'maxl', 'th', 'd2', 'compression_factor', 'volmin', 'volmax', 'x_size', 'y_size', 'z_size'};
paramValues = [pixelsize, minl, maxl, th, d2, compression_factor, volmin, volmax, x_size, y_size, z_size];

% Define comments (default: empty, except for 'volmax')
paramComments = { 'um/px', '', '', '', 'px', '', 'voxel', 'voxel', 'um', 'um', 'um' };

% Convert to table
paramTable = table(paramNames', paramValues', paramComments', 'VariableNames', {'Parameter', 'Value', 'Units'});

% Display the table
disp(paramTable);

% Save as CSV file
writetable(paramTable, fullfile(resultsfolder, 'parameters.csv'));

disp('Parameter table saved as parameters.csv');

% Initialize cell arrays for local results
local_table_11 = {};
local_table_22 = {};
local_table_33 = {};
local_table_44 = {};

file_axe = [result_axe '/Results_STED_Mask_SPU_axe_' filevector{1} '-' filevector{end} '_final.csv'];  
file_count = [result_count '/Results_STED_Mask_SPU_count_' filevector{1} '-' filevector{end} '_final.csv'];  
file_vol = [result_volume '/Results_STED_Mask_SPU_vol_' filevector{1} '-' filevector{end} '_final.csv'];  
file_ratio = [result_aspect_ratio '/Results_STED_Mask_SPU_ratio_' filevector{1} '-' filevector{end} '_final.csv'];  


%% Process the assigned files
for cart=1:length(filevector) 
    table_11 = table();
    table_22 = table();
    table_33 = table();
    table_44 = table();

    tstart1= tic;
    % get name of directory
    disp(fullfile(datpath, [filevector{cart} '_XY-OTSU']))
    %dir_cart = dir(fullfile(datpath, [filevector{cart} '_XY-OTSU']));
    %disp(dir_cart)
    datname = [filevector{cart} '_XY-OTSU'];
    disp(datname)
    % Search for files matching the pattern in the current directory
    maschlist = fullfile(datpath, datname, 'Mask_*_d.tif');        
    maschlist = dir(maschlist);

    % create folder
    colouredoverlaycart=fullfile(resultsfolder, '/Coloured_regions/', datname);
    if ~exist(colouredoverlaycart, 'dir') % creates results folder
        mkdir(colouredoverlaycart)
    end

    % parallel computing
    spmd    
    
        % Determine the number of files each worker will handle
        numWorkers = numlabs; % Total number of workers
        workerID = labindex;
        disp(['Worker ID: ', num2str(workerID)]);
    
        numFiles = length(maschlist);
        %disp(maschlist(1).name);
        %disp(maschlist(end).name);
        spmdIndex = labindex; % Index of the current worker
        filesPerWorker = ceil(numFiles / numWorkers);
        startIdx = (spmdIndex - 1) * filesPerWorker + 1;
        endIdx = min(spmdIndex * filesPerWorker, numFiles);

        disp("Indices")
        disp(startIdx)
        disp(endIdx)

         % initialize for each worker 
        count = zeros(length(maschlist), 1); % Initialize SPU count with zeros
        volume = zeros(length(maschlist), 1); %{}; %zeros(length(maschlist), length(count));
        aspect_ratio = zeros(length(maschlist), 1); %{}; %zeros(length(maschlist), length(count)); 
        axes = {}; %cell(length(maschlist), length(count));  % Create a 2D cell array

        for masch=startIdx:endIdx %1:size(maschlist,1)

            %disp(masch)
            tstart2=tic;  
            % or current_dir = cartlist(cart) since this isn't the dir
            current_dir = fullfile(datpath, datname);
            filename = fullfile(current_dir, maschlist(masch).name);   
            disp(filename)
            fileinfo=imfinfo(filename);% array of information on single images
            width=fileinfo(1).Width;
            height=fileinfo(1).Height;
            %read 3D tifs
    
            %% Load tiff z-stack and produce matlab data matrix
            framenum = numel(fileinfo);     % maximal frame number analyzed in this stack
            tiflink = Tiff(filename,'r');
          
            for frame=1:framenum % number of images in tif array
                tiflink.setDirectory(frame);
                data(:,:,frame)=tiflink.read();
            end
    
            tend=toc(tstart2);
        
            fprintf('Data acquired in: %.1f s.\n',tend);
            DAT=tend;
   
            window_data = data;
    
            window_height = size(window_data, 1);
            window_width = size(window_data, 2);
        
            % bin pixels of data set to reduce runtime
            window_data = uint16(imresize3(window_data, compression_factor)); % Data binning, last argument compression factor
            % calc new width and height
            binned_height = ceil(window_height * compression_factor);
            binned_width = ceil(window_width * compression_factor);
            binned_framenum = ceil(framenum * compression_factor);

            % Because we have a different unit conversion after the 
            % interpolation due to blurring of OTSU masks in the MG code, 
            % we need to consider the original data here too. 
            % Name matching raw data to make sure it is the right one

            raw_id = datname(1:end-8); % Adjust relevant part of naming  
            match_idx = 0;

            disp(raw_id)
            for b=1:length(rawdata_path)
                %{
                % for STED old
                % Split the rawdata_name into parts based on spaces and underscores
                rawdata_name = rawdata_path(b).name;
                rawdata_parts = split(rawdata_name, {' ', '_'});  % Split by both space and underscore
                % Extract the relevant parts from rawdata_name (e.g., 'C1', 'hires', '1')
                raw_name = strjoin({rawdata_parts{1}, rawdata_parts{end-2}, rawdata_parts{end-1}}, '_');  % This extracts 'C1', 'hires', '1' with underscores between
                %}
                
                % for STED 2024
                rawdata_name = rawdata_path(b).folder; % according to folder structure
                splitPath = strsplit(rawdata_name, filesep);
                raw_name = splitPath{end-1}; % This grabs 'ctr_A_04_external'
                
                        
                % Find the corresponding raw data file
                if contains(raw_name, raw_id)
                    match_idx = b; % Store the index of the match
                    break; % Stop looping after finding the first match
                end            
            end

            disp(raw_name)
            disp(match_idx)
            
            % get info about rawdata file
            fileinfo_og = imfinfo(fullfile(rawdata_path(match_idx).folder, rawdata_path(match_idx).name)); % Get metadata only
            framenum_og = numel(fileinfo_og); % Count total frames
            width_og = fileinfo_og(1).Width; % Get image width
            height_og = fileinfo_og(1).Height; % Get image height

            % current frame number due to post-processing in mask generation
            framenum_SPU = size(window_data, 3); 

            % unit conversion with respect to the file before mask creation
            % (post-processing)
            x_size_1 = (x_size * width_og / width);
            y_size_1 = (y_size * height_og / height);
            z_size_1 = (z_size * framenum_og / framenum_SPU);
          
            voxel_size = x_size_1 * y_size_1 * z_size_1; 

            % resize volmax, volmin
            volmax_1 = volmax * compression_factor^3;
            volmin_1 = volmin * compression_factor^3;
            
            tend=toc(tstart2);
        
            fprintf('Data reduced in: %.1f s.\n',tend-DAT);
            DAT=tend;
           
    
        %% OTSU Multithresholding Segmentation and SPU identification
            %disp(cart)
    
            %disp(masch)
            disp(maschlist(masch).name)
            disp(size(window_data))
            % multiple otsu thresholding to identify the SPU
            [MGtable, bw] = otsu_multithresholding(window_data, th, minl, maxl, volmax_1, volmin_1);    
            
            tend=toc(tstart2);
                    
            fprintf('Segmentation done in: %.1f s.\n',tend-DAT);
            DAT=tend;
            
    
        %% Region distinguishment
            % The same distinguishment is done here as for twophoton data
            % (different from STED otsu masks criterium). 
            % We don't have blurring before this step. 
            MGtable = regions(MGtable, th, d2);
                
            tend=toc(tstart2);
        
            fprintf('Region distinguishment done in: %.1f s.\n',tend-DAT);
            DAT=tend;

        %% Summarize
            datsize=size(window_data);
            glos=MGtable; % Working copy of whole table
            centdat=MGtable.Centroid; % Working copy of centroid coordinates
            voldat=MGtable.Volume; % Working copy of volumes
            axdat=MGtable.PrincipalAxisLength; % Working copy of axes
            idxdat=MGtable.VoxelIdxList; % Working copy of all points within objects
            thdat=MGtable.Thresh;
            %voxels=MGtable.VoxelList;
    
            %disp(MGtable)

        %% Cluster count
            % consider only appropriate SPUs
            [pos1, vol1, axe1, idx1, th1] = cluster_count(MGtable, centdat, voldat, axdat, idxdat, thdat);
            
            %if isempty(vol1) 
            %    continue
            %end
                
            tend=toc(tstart2);
            
            fprintf('Cluster count done in: %.1f s.\n',tend-DAT);
            DAT=tend;
  
        
        %% Save colour coded regions
           
            disp("This is proper mask name")
            disp(maschlist(masch).name)
            %{
            if cart==1

                if ismember(maschlist(masch).name, {'Mask_40_d.tif'})
                    disp("hi")
                    %reduce number of plotted frames
                    %binned_framenum = 1;
    
                    file_n=[colouredoverlaycart '/composite_region_' maschlist(masch).name]; % nome del file che creo
                    
                    big = 4500 * compression_factor^3; % declare the maximal volume after which it will be plotted in grey 
                
                    % create matrix with linear indexing of regions
                    M = zeros(size(window_data));
                    % iterate over regions
                    for i = 1:size(pos1, 1) 
                       M(idx1{i}) = i;
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
                        for i = 1:size(pos1, 1)
                            % update overlay for every region with another colour 
                            % Get the region mask for the current region and frame
                            region_mask = M == i;
                            % Overlay the region mask onto the original image + total mask
                            % Change colour per region
                            %{
                            if size(idx1{i}, 1) >= big 
                                overlay_region(:,:,:,frame) = imoverlay(overlay_region(:,:,:,frame), region_mask(:,:,frame), [0.5 0.5 0.5]);    
                            else
                                overlay_region(:,:,:,frame) = imoverlay(overlay_region(:,:,:,frame), region_mask(:,:,frame), colours(i,:));    
            
                            end
                            %}
                            overlay_region(:,:,:,frame) = imoverlay(overlay_region(:,:,:,frame), region_mask(:,:,frame), colours(i,:));    
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
            
                    fprintf('Overlay data and coloured regions saved as TIF file in: %.1f s.\n',tend-DAT);
                    DAT=tend;
                    
                end 
            end  
            %}
 
        
        %% Resize data
            % resize vol1, axe1 
            vol1 = vol1 / compression_factor^3;
            axe1 = axe1 / compression_factor;
        
            
        %% Calculate aspect ratio            
            % calc aspect ratio
            ratio = zeros(numel(vol1), 1);
            for l=1:numel(vol1)    
                % format data for csv
    
                if axe1(l,1) ~=0 
                    ratio(l) = max(axe1(l,:)) ./ min(axe1(l,:));
                else
                    ratio(l) = 0;
                end
        
            end

            name = sprintf('%s', maschlist(masch).name(1:end-6));
            %disp(name)            
                 

        %% Unit conversio in um^3 and correct index sorting 
            % index sorting to make sure the SPU row noumber corresponds to
            % the right mask for SPU density calculation

            % original sizes in um
          
            % volume:
            vol1 = vol1 .* voxel_size;
            % axes:
            axe1 = axe1 .* [x_size_1 y_size_1 z_size_1];

            % write vol in csv
            % ensure proper sorting according to index of MG mask (row) here
            % so that the SPU count corresponds to the right MG volume directly
            MG_index = str2num(maschlist(masch).name(6:end-6));
            count(MG_index) = length(vol1);
            %count(masch) = length(vol1);
            volume(MG_index) = mean(vol1);   
            aspect_ratio(MG_index) = mean(ratio);
            axes{MG_index} = [axe1(:, 1), axe1(:, 2), axe1(:, 3)];

            fprintf('Worker %d count contents:\n', workerID);
            %disp(count);  % Display the table for each worker

            tend=toc(tstart1);
            fprintf('Data of masks %d saved in: %.1f s.\n', masch, tend);
            DAT=tend;   

        end   
       
    end

    fprintf('SPMD DONE');

 %% Gather results from all workers
    % After parallel execution, gather data from the Composite

    % Use gcat to concatenate the non-empty results across all workers
    count = gcat(count, 1, 1);  % Concatenate along dimension 1
    count_brain = zeros(1, length(count{1}));

     % Gather 'volume' (different sizes)
    volume = gcat(volume, 1, 1);  % Gather volume into a nested cell array (because sizes differ)
    %volume = [volume{:}]; % flatten nested cell array
    volume_brain = zeros(1, length(volume{1}));

    % Gather 'ratio' (different sizes)
    aspect_ratio = gcat(aspect_ratio, 1, 1);  % Gather ratio into a nested cell array
    %aspect_ratio = [aspect_ratio{:}]; % flatten nested cell array
    aspect_ratio_brain = zeros(1, length(aspect_ratio{1}));

    %{
    axes = gcat(axes, 1, 1);  % Gather p_vr into a nested cell array 
    axes = [axes{:}]; % flatten nested cell array
    axes_brain = zeros(1, length(axes{1}));
    %}

    % correlation value and count
    % Combine non-zero elements from each worker into `count_brain` 
    for k = 1:numel(count)
        current_count = count{k};
        count_brain(current_count ~= 0) = current_count(current_count ~= 0);

        current_volume = volume{k};
        volume_brain(current_volume ~= 0) = current_volume(current_volume ~= 0);

        current_ratio = aspect_ratio{k};
        aspect_ratio_brain(current_ratio ~= 0) = current_ratio(current_ratio ~= 0);
        % axes
    end
    disp(k)
    % transpose
    count = count_brain';
    
    % Volume, axes and Aspect ratio
    % transpose
    volume = volume_brain';
    aspect_ratio = aspect_ratio_brain';
    % mask number are headers here, volumes of single SPUs in column
           
    tend=toc(tstart1);
    fprintf('Cart %s done in: %.1f s.\n', filevector{cart}, tend);
    DIT = tend;

        
    %% Write into tables per file
    % it is easier to gather in final file in the end, but better for
    % debugging if we seperate it. Concatenating the single tables later
    
    %num_files = numel(maschlist); % Get number of files
    %numbers = 1:num_files; % Create a sequential array
    disp("vol")
    % write vol in csv
    vol_name = [result_volume '/Results_STED_SPU_vol_' filevector{cart} '.csv'];  
    header_11 = sprintf('MEANVolume_um3_%s', filevector{cart});
    table_11_new = table(volume, 'VariableNames', {header_11});
    table_11 = save_table(table_11_new, table_11, vol_name, cart, 1);
    
    %disp("ratio")
    % save aspect ratio as csv
    ratio_name = [result_aspect_ratio '/Results_STED_SPU_ratio_' filevector{cart} '.csv'];   
    header_22 = sprintf('MEANAspect_ratio_vx_%s', filevector{cart});
    table_22_new = table(aspect_ratio, 'VariableNames', {header_22});
    table_22 = save_table(table_22_new, table_22, ratio_name, cart, 1);
    
    %disp("count")
    % save data in table
    count_name = [result_count '/Results_STED_SPU_count_'  filevector{cart} '.csv'];
    header_33 = sprintf('Number_%s', filevector{cart});
    table_33_new = table(count, 'VariableNames', {header_33});
    table_33 = save_table(table_33_new, table_33, count_name, cart, 1);
    

    %{
    disp("axes")
    % save data in table
    axe_name = [result_axe '/Results_STED_SPU_axe_' filevector{cart} '.csv'];
    header_44 = arrayfun(@(x) sprintf('Axes_um_%d', x), numbers, 'UniformOutput', false);
    table_44_new = table(axes, 'VariableNames', {header_44});
    table_44 = save_table(table_44_new, table_44, axe_name, cart, 1);
    %}
    

end

% The result is on table per property per brain that can be concatenated
% accross the other brains for further processing. For overview and
% debugging reasons, I keep it like this here and concatenate with a
% different script afterwards. 


%%FUNCTIONS
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function [MGtable, bw] = otsu_multithresholding(data, th, minl, maxl, volmax_1, volmin_1)           
    % thesholding to find segmented regions
    % Different thresholds are considered to compensate intensity variation
    % due to the experimental procedure. 

    % initialize to safe runtime 
    bw = logical(zeros(size(data))); % create logical array to prevent rounding and under segmentation
    MGdata = cell(1, th);  % Preallocate cell array
    for thresh=1:th
        level=minl+(thresh-1)*(maxl-minl)/(th-1); %choose threshold level
        for frame=1:size(data, 3)
            bw(:,:,frame) = im2bw(data(:,:,frame),level); %convert gray level to binary image
        end

        % Extract properties
        props = regionprops3(bw,'Centroid','Volume','VoxelIdxList','PrincipalAxisLength','Orientation', "BoundingBox");
                
        % Ensure VoxelIdxList is stored as a cell array
        if ~iscell(props.VoxelIdxList)
            props.VoxelIdxList = num2cell(props.VoxelIdxList);
        end
        %if ~iscell(props.VoxelList)
         %   props.VoxelList = num2cell(props.VoxelList);
        %end
        MGdata{thresh} = props;
        MGdata{thresh}.Thresh(:)=thresh;

    end

    %clear bw % clear to free memory
    
    MGtable=vertcat(MGdata{:}); % objects from all thresholds concatenated
    MGtable(MGtable.Volume>volmax_1,:)=[]; % removes >volmax structures from all threshold data
    MGtable(MGtable.Volume<volmin_1,:)=[];      % removes volumes < 3 voxels from all threshold data to fit an ellipsoid (used to be 3)
    clear MGdata % clear to free memory
end


function [vol, ovmg] = labeling_volumes(pos1, vol1, axe1, idx1, datsize)
    % sort MGs by ascending volume
    [vol,volidx] = sort(vol1);
    pos = pos1(volidx,:);
    axe = axe1(volidx,:);
    
    labels=zeros(datsize,'single');
    ovmg=0; %number of overlapping MG
    for k=1:size(vol1,2)
        if sum(labels(idx1{k}))>0 %already labels in MG volume?
            ovmg=ovmg+1;
        end
        labels(idx1{k})=k;
    end
    clear labels % clear to free memory    
end


function table_11 = save_table(table_11_new, table_11, file_name, f, startIdx)
    height_1 = size(table_11, 1);
    height_1_new = size(table_11_new, 1);
        
    if height_1_new < height_1
        padding = zeros(abs(height_1_new - height_1), size(table_11_new, 2));
        
        disp(class(table_11))
        disp(size(table_11))
        if iscell(table_11_new{end, end}) 
            padding = repmat({'0'}, abs(height_1_new - height_1), size(table_11_new, 2));
        end 

        table_11_new = [table_11_new; array2table(padding, 'VariableNames', table_11_new.Properties.VariableNames)];
    end
    if height_1_new > height_1
        padding = zeros(abs(height_1_new - height_1), size(table_11, 2));

        disp(class(table_11_new))
        disp(size(table_11))

        if iscell(table_11_new{end, end}) 
            padding = repmat({'0'}, abs(height_1_new - height_1), size(table_11, 2));
        end 
        
        table_11 = [table_11; array2table(padding, 'VariableNames', table_11.Properties.VariableNames)];
    end
        
    if f + 1 - startIdx == 1
        % Write the first table with headers
        table_11 = table_11_new;
        writetable(table_11, file_name, 'Delimiter', ',');
    else
        % Write the table to the CSV file
        table_11 = [table_11, table_11_new];
        % Append subsequent tables without headers
        writetable(table_11, file_name, 'Delimiter', ',');
    end
end



function [max_width, max_height] = window_dimension(rawdata, z_start, z_end)
    % Determine max window size
    max_height = 0;
    max_width = 0;
    for z = z_start:z_end
        current_frame = rawdata(:, :, z);
        % Define your mask logic here (non-zero or non-NaN)
        mask = ~isnan(current_frame) & current_frame > 0;
        if any(mask, 'all')
            [rows, cols] = find(mask);
            min_row = min(rows);
            max_row = max(rows);
            min_col = min(cols);
            max_col = max(cols);
            window_height = max_row - min_row + 1;
            window_width = max_col - min_col + 1;
            if window_height > max_height
                max_height = window_height;
            end
            if window_width > max_width
                max_width = window_width;
            end
        end
    end
end

function windowed_snippets = window(rawdata, z_start, z_end, windowed_snippets, padded_snippet)
% window the data with adjusted logic for padded windowed_snippets
    for z = z_start:z_end
        current_frame = rawdata(:, :, z);
        mask = ~isnan(current_frame) & current_frame > 0;
        if any(mask, 'all')
            [rows, cols] = find(mask);
            min_row = min(rows);
            max_row = max(rows);
            min_col = min(cols);
            max_col = max(cols);
            window_height = max_row - min_row + 1;
            window_width = max_col - min_col + 1;

            % Extract the windowed snippet
            windowed_snippet = current_frame(min_row:max_row, min_col:max_col);

            % Pad the snippet to match the maximum size
            padded_snippet(1:window_height, 1:window_width) = windowed_snippet;

            % Store the padded snippet
            windowed_snippets(:, :, z - z_start + 1) = padded_snippet;
        end
    end
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
    

    
        
