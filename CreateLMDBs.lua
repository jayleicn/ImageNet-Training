require 'image'
require 'xlua'
require 'lmdb'

local gm = require 'graphicsmagick'
local DataProvider = require 'DataProvider'
local config = require 'Config'

-------------------------------Settings----------------------------------------------
-- rescale the image without change its aspect ratio, the final ouput is a 3*H*W, min(H, W) = config.ImageMinSide
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

        cursor:put(config.Key(i),data, lmdb.C.MDB_NODUPDATA)  --config.Key(i) generate a formated stringed_number "
        if i % 1000 == 0 then
            txn:commit()
            print(env:stat())
            collectgarbage()
            txn = env:txn()
            cursor = txn:cursor()
        end
        xlua.progress(i,filenamesProvider:size())
    end
    txn:commit()
    env:close()

end


local TrainingFiles = DataProvider.FileSearcher{
    Name = 'TrainingFilenames',
    CachePrefix = config.TRAINING_DIR,
    MaxNumItems = 1e8,
    CacheFiles = true,
    PathList = {config.TRAINING_PATH},
    SubFolders = true,
    Verbose = true
}
local ValidationFiles = DataProvider.FileSearcher{
    Name = 'ValidationFilenames',
    CachePrefix = config.VALIDATION_DIR,
    MaxNumItems = 1e8,
    PathList = {config.VALIDATION_PATH},
    Verbose = true
}

local TrainDB = lmdb.env{
    Path = config.TRAINING_DIR,
    Name = 'TrainDB'
}

local ValDB = lmdb.env{
    Path = config.VALIDATION_DIR,
    Name = 'ValDB'
}

TrainingFiles:shuffleItems()
LMDBFromFilenames(ValidationFiles, ValDB)
LMDBFromFilenames(TrainingFiles, TrainDB)
