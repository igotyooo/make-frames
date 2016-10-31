require 'torch'
require 'paths'
require 'image'
require 'ffmpeg'

local function readLinesFrom( fpath )
        lines = {}
        for line in io.lines( fpath ) do
                lines[#lines + 1] = line
        end
        return lines
end
local function findStringIndex( arr, str )
        for idx, str_ in pairs( arr ) do
                if str_ == str then return idx end
        end
end
local function parse( arg )
        local cmd = torch.CmdLine(  )
        cmd:text(  )
        cmd:text( 'Frame extraction of UCF-101.' )
        cmd:text(  )
        cmd:text( 'Options:' )
        cmd:option( '-srcLabelDir', '/home/dgyoo/workspace/datain/UCF101/ucfTrainTestlist/',
                'Path to the directory containing set lists.' )
        cmd:option( '-srcVideoDir', '/home/dgyoo/workspace/datain/UCF101/data',
                'Path to the directory containing videos.' )
        cmd:option( '-dstDir', '/home/dgyoo/workspace/datain/UCF101FRAME/',
                'Path to the output directory.' )
        cmd:option( '-desiredShortSide', 240,
                'Desired short side after resize.' )
        cmd:option( '-desiredFPS', 10,
                'Desired FPS in which frames are extracted.' )
        cmd:option( '-imageType', 'jpg',
                'Frame image format to be stored in.' )
        cmd:option( '-divisionId', 1,
                'Division ID of train/test division in UCF-101.' )
        cmd:option( '-numThreads', 8,
                'Number of worker.' )
        cmd:text(  )
        return cmd:parse( arg or {} )
end
local function findStringIndex( arr, str )
        for idx, str_ in pairs( arr ) do
                if str_ == str then return idx end
        end
end

---------------
-- Main script.
---------------
local opt = parse( arg )
print( opt )
local dstDataDir = paths.concat( opt.dstDir, 'data' )
paths.mkdir( dstDataDir )
-- Make and write class list in destination.
local fp_cname = io.open( paths.concat( opt.dstDir, 'db_cid2name.txt' ), 'w' )
local cid2name = readLinesFrom( paths.concat( opt.srcLabelDir, 'classInd.txt' ) )
for cid, cname in pairs( cid2name ) do
        cid2name[ cid ] = cid2name[ cid ]:match( '%d+%s+(.+)%s' )
        fp_cname:write( cid2name[ cid ], '\n' )
end
io.close( fp_cname )
-- Make video list.
local vid2path = {  }
local vid2cid = {  }
local vid2setid = {  }
local setNames = { 'train', 'test' }
print( 'Read video file list.' )
for setid, setName in pairs( setNames ) do
        fpath = paths.concat( opt.srcLabelDir, setName .. 'list0' .. opt.divisionId .. '.txt' )
        local lines = readLinesFrom( fpath )
        print( fpath .. ' contains ' .. #lines .. ' videos.' )
        for l, str in pairs( lines ) do
                local vpath, cid
                if setName == 'train' then
                        vpath, cid = str:match( '.+/(.+)%s+(%d+)' )
                        cid = tonumber( cid )
                        vpath = paths.concat( opt.srcVideoDir, vpath )
                else
                        local cname = str:match( '(.+)/.+%..+' )
                        cid = findStringIndex( cid2name, cname ) assert( cid )
                        vpath = paths.concat( opt.srcVideoDir, str:match( '.+/(.+)%s' ) )
                end
                vid2path[ #vid2path + 1 ] = vpath
                vid2cid[ #vid2cid + 1 ] = cid
                vid2setid[ #vid2setid + 1 ] = setid
        end
end
assert( #vid2path == #vid2cid and #vid2path == #vid2setid )
print( #vid2path .. ' videos found in total.' )
print( 'Done.' )
-- local tdb = require( 'fb.debugger' ) tdb.enter(  )
-- Extract video frames and write label files.
local fp_vpath = io.open( paths.concat( opt.dstDir, 'db_vid2path.txt' ), 'w' )
local fp_cid = io.open( paths.concat( opt.dstDir, 'db_vid2cid.txt' ), 'w' )
local fp_setid = io.open( paths.concat( opt.dstDir, 'db_vid2setid.txt' ), 'w' )
for vid, vpath in pairs( vid2path ) do
        assert( paths.filep( vpath ) )
        local cid = vid2cid[ vid ]
        local cname = cid2name[ cid ]
        local setid = vid2setid[ vid ]
        local vname = paths.basename( vpath )
        vname = vname:match( '(.+)%..+' )
        local dstFrameDir = paths.concat( dstDataDir, vname )
        paths.mkdir( dstFrameDir )
        local handle = io.popen( string.format( 'ffprobe -v error -show_streams %s | grep coded_', vpath ) )
        local width, height = handle:read( '*a' ):match( '.+width=(%d+).+height=(%d+)' )
        local scale
        if tonumber( width ) > tonumber( height ) then
                scale = string.format( '-1:%d', opt.desiredShortSide )
        else
                scale = string.format( '%d:-1', opt.desiredShortSide )
        end
        local command = string.format(
        'ffmpeg -i %s -threads %d -qscale:v 2 -vf "scale=%s,fps=%d" -loglevel error %s/%%04d.%s',
        vpath, opt.numThreads, scale, opt.desiredFPS, dstFrameDir, opt.imageType )
        os.execute( command )
        fp_vpath:write( './data/' .. vname, '\n' )
        fp_cid:write( cid, '\n' )
        fp_setid:write( setid, '\n' )
        print( string.format( '[%d%%] %d/%d dumped.', 100 * vid / #vid2path, vid, #vid2path ) )
end
io.close( fp_vpath )
io.close( fp_cid )
io.close( fp_setid )
print( 'Done.')
