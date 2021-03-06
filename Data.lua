require 'xlua'
require 'lmdb'


local DataProvider = require 'DataProvider'
local config = require 'Config'


function ExtractFromLMDBTrain(data)
    
    -- two items Name, Data in one LMDB entry
    local wnid = string.split(data.Name,'_')[1]
    local class = config.ImageNetClasses.Wnid2ClassNum[wnid]  -- from here we can also get coarse labels
    -- local class_coarse, class_fine
    local img = data.Data
    if config.Compressed then
        img = image.decompressJPG(img,3,'byte')
    end

    if math.min(img:size(2), img:size(3)) ~= config.ImageMinSide then
        img = image.scale(img, '^' .. config.ImageMinSide)
    end
    
    
    -- Data augementation
    require 'image'
    
    -- narrow(dim,index,size) an view of the storage in dimmension [dim], from index to index+size-1
    local reSample = function(sampledImg)
        local sizeImg = sampledImg:size()
        local szx = torch.random(math.ceil(sizeImg[3]/4)) -- width
        local szy = torch.random(math.ceil(sizeImg[2]/4)) -- height
        local startx = torch.random(szx)
        local starty = torch.random(szy)
        return image.scale(sampledImg:narrow(2,starty,sizeImg[2]-szy):narrow(3,startx,sizeImg[3]-szx),sizeImg[3],sizeImg[2])
    end
    
    local rotate = function(angleRange)
        local applyRot = function(Data)
            local angle = torch.randn(1)[1]*angleRange
            local rot = image.rotate(Data,math.rad(angle),'bilinear')
            return rot
        end
        return applyRot
    end
    
    if config.Augment == 3 then
        img = rotate(0.1)(img)
        img = reSample(img)
    elseif config.Augment == 2 then
        img = reSample(img)
    end
    
    -- crop img randomly to the model.InputSize OR default config.InputSize {3,224,224}
    local startX = math.random(img:size(3)-config.InputSize[3]+1)
    local startY = math.random(img:size(2)-config.InputSize[2]+1)
    img = img:narrow(3,startX,config.InputSize[3]):narrow(2,startY,config.InputSize[2])

    -- mirror (horizontally)
    local hflip = torch.random(2)==1
    if hflip then
        img = image.hflip(img)
    end

    return img, class
end

function ExtractFromLMDBTest(data)
    require 'image'
    local wnid = string.split(data.Name,'_')[1]
    local class = config.ImageNetClasses.Wnid2ClassNum[wnid]
    local img = data.Data
    if config.Compressed then
        img = image.decompressJPG(img,3,'byte')
    end

    if (math.min(img:size(2), img:size(3)) ~= config.ImageMinSide) then
        img = image.scale(img, '^' .. config.ImageMinSide)
    end
    
    
    local startX = math.ceil((img:size(3)-config.InputSize[3]+1)/2)  -- Why /2
    local startY = math.ceil((img:size(2)-config.InputSize[2]+1)/2)
    img = img:narrow(3,startX,config.InputSize[3]):narrow(2,startY,config.InputSize[2])
    
    return img, class
end

-- simply a formation of the numbers; eg. tensor --> tb1, 234 --> "0000234"     
function Keys(tensor)
    local tbl = {}
    for i=1,tensor:size(1) do
        tbl[i] = config.Key(tensor[i])
    end
    return tbl
end


function EstimateMeanStd(DB, typeVal, numEst)
    local typeVal = typeVal or 'simple'  -- normalize type, all-images/channel-wise/
    local numEst = numEst or 10000
    local x = torch.FloatTensor(numEst ,unpack(config.InputSize))
    local randKeys = Keys(torch.randperm(DB:size()):narrow(1,1,numEst))  --randKeys will be a formatted randperm
    DB:CacheRand(randKeys, x)  -- discard the label arg, the data will be stored in local variable "x"
    local dp = DataProvider.Container{  
        Source = {x, nil}
    }
    return {typeVal, dp:normalize(typeVal)}  -- normalize type, mean, std   -- x has been normalized
end

local TrainDB = DataProvider.LMDBProvider{
    Source = lmdb.env({Path = config.TRAINING_DIR, RDONLY = true}),
    ExtractFunction = ExtractFromLMDBTrain
}
local ValDB = DataProvider.LMDBProvider{
    Source = lmdb.env({Path = config.VALIDATION_DIR , RDONLY = true}),
    ExtractFunction = ExtractFromLMDBTest
}



return {
    ImageNetClasses = config.ImageNetClasses,
    ValDB = ValDB,
    TrainDB = TrainDB,
}
