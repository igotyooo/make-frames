require 'torch'
require 'paths'
require 'image'
require 'ffmpeg'
require 'sys'

local function parse( arg )
	local cmd = torch.CmdLine(  )
	cmd:text(  )
	cmd:text( 'Frame extraction of Charades dataset.' )
	cmd:text(  )
	cmd:text( 'Options:' )
	cmd:option( '-srcLabelDir', '/home/dgyoo/workspace/datain/CHARADES_V1/Charades/',
	'Path to the directory containing labels.' )
	cmd:option( '-srcVideoDir', '/home/dgyoo/workspace/datain/CHARADES_V1/Charades_v1_480/',
	'Path to the directory containing videos.' )
	cmd:option( '-dstDir', '/home/dgyoo/workspace/datain/CHARADES_V1_FRAMES/',
	'Path to the output directory.' )
	cmd:option( '-desiredShortSide', 256,
	'Desired short side after resize.' )
	cmd:option( '-desiredFPS', 10,
	'Desired FPS in which frames are extracted.' )
	cmd:option( '-imageType', 'jpg',
	'Frame image format to be stored in.' )
	cmd:option( '-numThreads', 8,
	'Number of worker.' )
	cmd:text(  )
	return cmd:parse( arg or {} )
end

---------------
-- Main script.
---------------
local opt = parse( arg )
print( opt )
paths.mkdir( opt.dstDir )
srcSetName = { 'train', 'test' }
dstSetName = { 'train', 'val' }
for setid = 1, 2 do
	-- Make cid2name.
	local fp_cid2name = io.open( paths.concat( opt.dstDir, 'db_cid2name.txt' ), 'w' )
	for line in io.lines( paths.concat( opt.srcLabelDir, 'Charades_v1_classes.txt' ) ) do
		fp_cid2name:write( line:match( '.-%s(.+)' ), '\n' )
	end
	io.close( fp_cid2name )
	-- Make vid2name.
	local srcLabelPath = paths.concat( opt.srcLabelDir, 'Charades_v1_' .. srcSetName[ setid ] .. '.csv' ) 
	local vid2name = {  }
	local fp_vid2name = io.open( paths.concat( opt.dstDir, 'db_' .. dstSetName[ setid ] .. '_vid2name.txt' ), 'w' )
	local vid = -1
	for line in io.lines( srcLabelPath ) do
		vid = vid + 1
		if vid ~= 0 then
			local vname = line:match( '(.-),.+$' )
			fp_vid2name:write( vname, '\n' )
			vid2name[ vid ] = vname
		end
	end
	local numVideo = #vid2name
	io.close( fp_vid2name )
	-- Extract frames.
	local dstFrameDir = paths.concat( opt.dstDir, 'data' )
	paths.mkdir( dstFrameDir )
	for vid, vname in pairs( vid2name ) do
		local vpath = paths.concat( opt.srcVideoDir, vname .. '.mp4' )
		assert( paths.filep( vpath ) )
		local dstFrameDir_ = paths.concat( dstFrameDir, vname )
		paths.mkdir( dstFrameDir_ )
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
		vpath, opt.numThreads, scale, opt.desiredFPS, dstFrameDir_, opt.imageType )
		os.execute( command )
		print( ( '%s %d%% (%d/%d) dumped.' ):format( dstSetName[ setid ], 100 * vid / numVideo, vid, numVideo ) )
	end
	-- Make vid2numf.
	local vid2numf = {  }
	local fp_vid2numf = io.open( paths.concat( opt.dstDir, 'db_' .. dstSetName[ setid ] .. '_vid2numf.txt' ), 'w' )
	for vid, vname in pairs( vid2name ) do
		local vpath = paths.concat( opt.srcVideoDir, vname .. '.mp4' )
		assert( paths.filep( vpath ) )
		local dstFrameDir_ = paths.concat( dstFrameDir, vname )
		local numf = tonumber( sys.fexecute( ( 'find %s | wc -l' ):format( paths.concat( dstFrameDir_, '*.' .. opt.imageType ) ) ) )
		fp_vid2numf:write( ( '%d\n' ):format( numf ) )
		vid2numf[ vid ] = numf
		print( ( '%s %d%% (%d/%d) #frame counted.' ):format( dstSetName[ setid ], 100 * vid / numVideo, vid, numVideo ) )
	end
	io.close( fp_vid2numf )
	-- Make aid2vid, aid2loc, aid2cid.
	local fp_aid2vid = io.open( paths.concat( opt.dstDir, 'db_' .. dstSetName[ setid ] .. '_aid2vid.txt' ), 'w' )
	local fp_aid2loc = io.open( paths.concat( opt.dstDir, 'db_' .. dstSetName[ setid ] .. '_aid2loc.txt' ), 'w' )
	local fp_aid2cid = io.open( paths.concat( opt.dstDir, 'db_' .. dstSetName[ setid ] .. '_aid2cid.txt' ), 'w' )
	local aid2cid = {  }
	local vid = -1
		  local spf = 1 / opt.desiredFPS
		  for line in io.lines( srcLabelPath ) do
					 vid = vid + 1
					 if vid ~= 0 then
								local actions = line:match( '.+,(.-)$' ):split( ';' )
								local numAction = #actions
								for a, str in pairs( actions ) do
										  local str_ = str:split( ' ' )
										  if #str_ == 1 then break end -- No label.
										  local cid = tonumber( str_[ 1 ]:match( 'c(%d+)' ) ) + 1
										  local numf = vid2numf[ vid ]
										  local tstart = math.floor( tonumber( str_[ 2 ] ) * opt.desiredFPS ) + 1
										  local tend = math.floor( tonumber( str_[ 3 ] ) * opt.desiredFPS ) + 1
										  if tstart >= numf or tstart >= tend then 
													 print( ( 'Reject video %d(%s) has larger tstart=%d(%.2f) than numf=%d.' ):format( vid, vid2name[ vid ], tstart, tonumber( str_[ 2 ] ), numf ) )
										  else
													 fp_aid2vid:write( ( '%d\n' ):format( vid ) )
													 fp_aid2loc:write( ( '%d %d\n' ):format( tstart, math.min( tend, numf ) ) )
													 fp_aid2cid:write( ( '%d\n' ):format( cid ) )
										  end
								end
					 end
		  end
		  io.close( fp_aid2vid )
		  io.close( fp_aid2loc )
		  io.close( fp_aid2cid )
end
