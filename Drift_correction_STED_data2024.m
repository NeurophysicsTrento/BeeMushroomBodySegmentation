% This code produces drift corrected tif files using the output files
% shift.txt from the Fiji plugin "Correct 3D Drift" and stores the total
% drift in a csv file. 
% 
% NOTE: 
% This code only investigates the new data of 2024 that ends on
% STAR RED STED.ome.tiff. 
% The data ending only on STAR RED is ignored here

clear all,close all    

%% CHOOSE HERE THE PATH

folderpath = '/home/amelieluise.fehrmann/STED';    % WRITE HERE THE PATH WHERE THE FOLDER "Matlab Analysis" IS STORED.
%folderpath = 'C:\Users\nicol\OneDrive\Desktop';   % example

%% setup path structure
datpath = dir(fullfile(folderpath, 'STED_data2024_new_shift'));
analyze_all_images = 1; % SET IT TO "1" TO ANALYZE ALL THE IMAGES IN THE FOLDER "Tiff images",
filevector={'ctr_A_04_external', 'ctr_A_04_internal'}; % Choose here the images to be analyzed like 'C1 1'

if analyze_all_images==1
    imagelist=datpath; % list of the files in "Tiff images" ending with "_image.tif"
    for im=1:length(imagelist)
        folderName = datpath(im).name;
        filevector{1, im} = folderName; % store the constructed filename in filevector
    end    
end

cartlist = {};
samplelist = {};
dirlist = {};
for item=1:length(filevector)
    %folderName = strsplit(datpath(item).name, '_'); % split into underscores
    %folderName = datpath(item).name;
    folderName = filevector{item};
    
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
            pattern1 = fullfile(samplelist{end}, '*STAR RED STED.ome.tiff');
            pattern2 = fullfile(samplelist{end}, '*STAR RED STED.tif'); % Replace with your second pattern

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

resultsfolder = '/home/amelieluise.fehrmann/STED/Results_STED_MASKS_test';   
if ~exist(resultsfolder, 'dir')  
   mkdir(resultsfolder) % creates the folder where results will be stored
end
    
table_11 = table([], 'VariableNames', {'var4'});


%% read tif file
% dirlist contains the whole paths to the images in samplefolders in varying carts
for dirn=1:length(dirlist)
    clearvars -except f filevector tstart1 tstart2 tend1 tend2 folders resultsfolder table_11 subsetcart results samp samplelist dirn dirlist cart cartlist dirlist folderpath datpath result 
    tstart1=tic;
    % get name of cart
    % Split the directory path by the file separator
    folders = strsplit(cartlist{dirn}, filesep);
    %dirlist(dirn).name  % prints on the command window the name of the image being analyzed
    wholename = fullfile(dirlist{dirn}.folder, dirlist{dirn}.name);
    % get info about corresponding cart
    %cart = fullfile(folders{end}, ' STAR RED STED');
    % get file info
    fileinfo=imfinfo(wholename);
    width=fileinfo(1).Width; height=fileinfo(1).Height;
    framenum = size(fileinfo,1);
    for frame=1:framenum% number of images in tif array
        rawdata(:,:,frame)=imread(wholename,frame);
    end


    %% read output file from Fiji plugin "Correct 3D Drift" containing drifts:
    % Open the file
    driftname = fullfile(dirlist{dirn}.folder, 'shifts.txt');
    fileID = fopen(driftname, 'r');

    % Skip the first two lines (header for ROI, column names for ROI)
    for k=1:2
         fgetl(fileID); % read and discard
    end

    % Read the ROI data
    roiData = textscan(fileID, '%d%d%d%d%d%d', 1);

    % Skip the next two lines(header for Shifts, 
    %column names for Shifts)
    for k=1:3
        fgetl(fileID);  % read and discard
    end

    % Read the Shifts data
    % is cell array with single cell containing matrix
    shiftData = textscan(fileID, '%f%f%f', 'CollectOutput', true);
    

    % Close the file
    fclose(fileID);

    % Convert cell arrays to matrices
    roiData = cell2mat(roiData);
    %shiftData = cell2mat(shiftData);
    shiftData = shiftData{1}; % convert into matrix without cell
    
    % Display the data
    %disp('ROI Data:');
    %disp(roiData);

    %disp('Shift Data:');
    %disp(shiftData);

    %% add the shift to rawdata
    % Initialize shifted data with zeros (black background)
    % adjust the color of the crop-background for better OTSU-segmentation
    frame = rawdata(:,:,1);
    grey_level = 128; %min(frame(frame > 0)); 
    %disp(grey_level)
    shiftedData = grey_level * ones(height, width, framenum, 'like', rawdata);

    for f = 1:framenum
        % Extract shift values for the current frame
        shiftX = shiftData(f, 1);
        shiftY = shiftData(f, 2);

        % Apply the shifts
        for y = 1:height
            for x = 1:width
                % Calculate new coordinates
                % shift is always negative in the file!
                newX = round(x - shiftX);
                newY = round(y - shiftY);

                % Ensure coordinates are within bounds
                if newX >= 1 && newX <= width && newY >= 1 && newY <= height
                    shiftedData(newY, newX, f) = rawdata(y, x, f);
                end
            end
        end
    end
    
    % shifted and non-windowed data, ensure compatibility
    data = uint16(min(max(shiftedData, 0), 65535));
    
    
    %{
    for f = 1:framenum
        % Extract shift values for the current frame
        shiftX = shiftData(f, 1);
        shiftY = shiftData(f, 2);

        % Create a meshgrid of coordinates
        [X, Y] = meshgrid(1:width, 1:height);

        % Compute new coordinates
        newX = X + shiftX;
        newY = Y + shiftY;

        % Ensure coordinates are within bounds by replicating boundary
        % values in out-of-bound cases
        newX = max(1, min(width, round(newX)));
        newY = max(1, min(height, round(newY)));
        
        
        % Create an empty frame for the shifted data
        shiftedFrame = zeros(height, width, 'like', rawdata(:,:,f));

        % Apply the shifts
        for x = 1:width
            for y = 1:height
                shiftedFrame = rawdata(newY(y,x), newX(y,x), f);
            end
        end

        % Store the shifted frame
        shiftedData(:,:,f) = shiftedFrame;
    end

    % Update rawdata with shifted data
    rawdata = shiftedData;
    %}
    
    %{
    %% Crop the image removing the black
    % find smallest dimension of ROI data in last frame
    mask = shiftedData(:,:,framenum) > grey_level;
    if any(mask, 'all')
        [rows, cols] = find(mask);
        min_row = min(rows);
        max_row = max(rows);
        min_col = min(cols);
        max_col = max(cols);
        
        window_height = max_row - min_row + 1;
        window_width = max_col - min_col + 1;
        
        for f = 1:framenum
            data(:,:,f) = shiftedData(min_row:max_row, min_col:max_col, f);
        end  
       
    end    
    %}
  

    %% save data in tif again
    file_n = fullfile(dirlist{dirn}.folder, ['drift_corrected_background_' dirlist{dirn}.name]);

    tifformat= reshape(data, height, width, 1, framenum);
    % Write 3D tiff
    s=whos('tifformat'); %size bigger than 32byte?
    if s.bytes > 2^32-1
       tfile = Tiff(file_n, 'w8'); % Big Tiff file
    else
       tfile = Tiff(file_n, 'w');
    end

    % write composite to TIF
    tagstruct.ImageWidth = width;
    tagstruct.ImageLength = height;
    tagstruct.PlanarConfiguration = Tiff.PlanarConfiguration.Chunky;
    tagstruct.Photometric = Tiff.Photometric.MinIsBlack;
    tagstruct.BitsPerSample = 16;
    tagstruct.SamplesPerPixel = 1; 
    for fr = 1:framenum
        tfile.setTag(tagstruct);
        tfile.write(data(:,:,fr));
        if fr ~= framenum
           tfile.writeDirectory();
        end
    end

    tfile.close();
    
    %% save total drift
    drift_name = [resultsfolder '/Results_STED_Mask_total_drift_' filevector{1} '-' filevector{end} '.csv'];   
    header = sprintf('drift_xy_%s \n', folders{end});
    % this table contains the total x-drift in first row and y-drift in second one per
    % each file in the columns
    table_11_new = table([shiftX(end); shiftY(end)], 'VariableNames', {header});
    table_11 = save_table(table_11_new, table_11, drift_name, dirn);

  
    tend1=toc(tstart1);
    fprintf('%s Drift corrected: %.1f s.\n', folders{end}, tend1);    
       
end
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function table_11 = save_table(table_11_new, table_11, file_name, f)
    height_1 = size(table_11, 1);
    height_1_new = size(table_11_new, 1);
        
    if height_1_new < height_1
        table_11_new = [table_11_new; array2table(zeros(abs(height_1_new - height_1), size(table_11_new, 2)), 'VariableNames', table_11_new.Properties.VariableNames)];
    end
    if height_1_new > height_1
        table_11 = [table_11; array2table(zeros(abs(height_1_new - height_1), size(table_11, 2)), 'VariableNames', table_11.Properties.VariableNames)];
    end
        
    if f == 1
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

