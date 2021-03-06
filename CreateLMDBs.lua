require 'image'
require 'xlua'
require 'lmdb'

local gm = require 'graphicsmagick'
local DataProvider = require 'DataProvider'
local config = require 'Config'

-------------------------------Settings----------------------------------------------
-- rescale the image without change its aspect ratio, the final ouput is a 3*H*W, min(H, W) = config.ImageMinSide＝256
-- In this part, the image data itself is only rescaled to have a min-side=256, aspect ratio stay the same, no crops here.
local PreProcess = function(Img)
    local im = image.scale(Img, '^' .. config.ImageMinSide) --minimum side of ImageMinSide

    if im:dim() == 2 then
        im = im:reshape(1,im:size(1),im:size(2))
    end
    if im:size(1) == 1 then
        im=torch.repeatTensor(im,3,1,1)
    end
    if im:size(1) > 3 then
        im = im[{{1,3},{},{}}]
    end
    return im
end

-- 
local LoadImgData = function(filename)
--    local img = gm.Image(filename):toTensor('float','RGB','DHW') -- Load images to tensor [filename is the file path] 
--  Why use gm to load?  for effecency?
    local img = image.load(filename, 3, 'float')
    if img == nil then
        print('Image is buggy')
        print(filename)
        os.exit()
    end
    img = PreProcess(img)
    -- any need to compress the images ???
    if config.Compressed then
        return image.compressJPG(img)
    else
        return img
    end
end


-- images are all named in the format "wnid_seriesNum"
function NameFile(filename)
    local name = paths.basename(filename,'JPEG')  --filename without path prefix and format suffix
    local substring = string.split(name,'_')  -- return a table

    if substring[1] == 'ILSVRC2012' then -- Validation file
        local num = tonumber(substring[3])
        return config.ImageNetClasses.ClassNum2Wnid[config.ValidationLabels[num]] .. '_' .. num
    else -- Training file
        return name
    end

end




function LMDBFromFilenames(filenamesProvider,env)
    env:open()
    local txn = env:txn()
    local cursor = txn:cursor()
    for i=1, filenamesProvider:size() do
        local filename = filenamesProvider:getItem(i)  --filename is the image full path
        local data = {Data = LoadImgData(filename), Name = NameFile(filename)} --image itself and its name as one entry

        cursor:put(config.Key(i),data, lmdb.C.MDB_NODUPDATA)  --config.Key(i) generate a formated stringed_number %07d
        if i % 1000 == 0 then  --store to disk every 1000 images
            txn:commit()
            print(env:stat())
            collectgarbage()
            txn = env:txn()
            cursor = txn:cursor()
        end
        xlua.progress(i,filenamesProvider:size())
    end
    txn:commit()  -- store the rest of the data entry
    env:close()

end

--DataProvider.
local TrainingFiles = DataProvider.FileSearcher{
    Name = 'TrainingFilenames',  --name of container
    CachePrefix = config.TRAINING_DIR,  -- where to the LMDB located
    MaxNumItems = 1e8,
    CacheFiles = true,  -- cache data into files
    PathList = {config.TRAINING_PATH},  -- where the images located  --!!! Maybe useful for me !!!
    SubFolders = true,  -- including images in the subfolders
    Verbose = true  --display msg
}

local ValidationFiles = DataProvider.FileSearcher{
    Name = 'ValidationFilenames', 
    CachePrefix = config.VALIDATION_DIR,
    MaxNumItems = 1e8,
    PathList = {config.VALIDATION_PATH},
    Verbose = true
}

local TrainDB = lmdb.env{
    Path = config.TRAINING_DIR,  -- LMDB location
    Name = 'TrainDB' -- LMDB name
}

local ValDB = lmdb.env{
    Path = config.VALIDATION_DIR,
    Name = 'ValDB'
}

TrainingFiles:shuffleItems()
LMDBFromFilenames(ValidationFiles, ValDB)
LMDBFromFilenames(TrainingFiles, TrainDB)
