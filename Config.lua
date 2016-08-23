local ImageNetClasses = torch.load('./ImageNetClasses')
-- nil the useless data entry
for i=1001,#ImageNetClasses.ClassName do
    ImageNetClasses.ClassName[i] = nil
end

--as lmdb entry keys
function Key(num)
    return string.format('%07d',num)
end


return
{
    TRAINING_PATH = '/home/ehoffer/Datasets/ImageNet/train/', --Training images location
    VALIDATION_PATH = '/home/ehoffer/Datasets/ImageNet/validation/',  --Validation images location
    VALIDATION_DIR = '/home/ehoffer/Datasets/ImageNet/LMDB/validation/', --Validation LMDB location
    TRAINING_DIR = '/home/ehoffer/Datasets/ImageNet/LMDB/train/', --Training LMDB location
    ImageMinSide = 256, --Minimum side length of saved images
    ValidationLabels = torch.load('./ValidationLabels'),  -- Torch Tensor, 50000*1, eg. ValidationLabels[1]=490
    ImageNetClasses = ImageNetClasses,
    Normalization = {'simple', 118.380948, 61.896913}, --Default normalization -global mean, std
    Compressed = true,
    Key = Key
}

-- ImageNetClasses -- Lua Table
-- ClassNum2Wnid    {1:n01972223, 2:n02234243, ...}
-- Wnid2ClassNum    nil, 
-- Description
-- ClassName
