async = require 'async'
path = require 'path'
child_process = require 'child_process'

JOB_QUEUE = "imageResizerJobs"
CONFIG_PROPERTY = "imageResizer"

getOption = (params, option, fallback) ->
  options = params.assemble.options[CONFIG_PROPERTY] ? {}
  options[option] ? fallback

postprocess = (params, callback) ->
  grunt = params.grunt
  
  jobs = params.assemble.options[JOB_QUEUE] ? {}  
  jobIds = Object.keys(jobs).reverse()
  
  srcRoot = getOption params, "srcRoot", "public"
  destRoot = getOption params, "destRoot", "dest"
  subpath = getOption params, "subpath", "resize-cache"
  
  iterator = (id, next) -> 
    job = jobs[id]
    src = path.join srcRoot, job.src
    dest = path.join destRoot, id
    line = "#{src} -> #{dest} "
    
    unless grunt.file.exists src
      grunt.log.write line
      grunt.log.error "MISSING"
      return next()
      
    if grunt.file.exists dest
      grunt.log.write line
      grunt.log.error "EXISTS"
      return next()
    
    child_process.execFile "identify", ['-format', '%w,%h,%[channels]', src], {}, (err, stdout) ->
      if err
        grunt.log.write line
        grunt.log.error err
        return next err
      
      info = stdout.split ","
      hasAlpha = info[2].indexOf("a") >= 0
      toJpeg = /\.jpe?g$/.test dest
      
      # if hasAlpha
      #   TODO
      
      size =
        width: Number(info[0])
        height: Number(info[1])
      
      widthScale = heightScale = 0
      widthScale = job.width / size.width if job.width
      heightScale = job.height / size.height if job.height
      
      doCrop = job.flags.indexOf("#") >= 0
      
      if doCrop or widthScale is 0 or heightScale is 0
        scale = Math.max widthScale, heightScale
      else
        scale = Math.min widthScale, heightScale
      
      scaled = 
        width: Math.round(size.width * scale)
        height: Math.round(size.height * scale)
        
      grunt.file.mkdir path.dirname dest
      
      args = [src]
      
      if hasAlpha and not /\.png$/.test dest
        args.push "-background", "white"
        args.push "-flatten"
        args.push "-alpha", "off"
      
      args.push "-gravity", "center" if doCrop
      args.push "-scale", "#{scaled.width}x#{scaled.height}"
      
      args.push "-crop", "#{job.width ? scaled.width}x#{job.height ? scaled.height}+0+0" if doCrop
      args.push "-quality", "78" if toJpeg
      
      args.push dest
      
      child_process.execFile "convert", args, {}, (err) -> 
        grunt.log.write line
        if err then grunt.log.error() else grunt.log.ok()
        next err
    
  async.eachLimit jobIds, 4, iterator, callback
  
preprocess = (params, callback) ->
  jobs = params.assemble.options[JOB_QUEUE] ?= {}
  
  makeId = ->
    subpath = getOption params, "subpath", "resize-cache"
    s = [arguments...].join("-")
    s = s.slice(1).replace(/\//g, "_").replace(/#/g, 'h').replace(/</g, 'l').replace(/>/g, 'r').replace(/!/g, 'b')
    "/#{subpath}/#{s}.jpg"
  
  enqueue = (src, dimensions) ->
    command = /^([0-9]*)x([0-9]*)(.*)$/.exec dimensions
    
    job =
      id: makeId(arguments...)
      src: src
      dimensions: dimensions
      width: Number(command[1]) if command[1].length > 0
      height: Number(command[2]) if command[2].length > 0
      flags: command[3]
    
    jobs[job.id] = job
    job.id
  
  params.assemble.engine.registerFunctions
    resize: (url) ->
      if url then enqueue(arguments...) else url
    
  callback()
    
module.exports = (params, callback) ->
  if params.stage is 'render:pre:pages'
    preprocess arguments...
  else if params.stage is 'render:post:pages'
    postprocess arguments...
  else
    callback()
    
module.exports.options =
  stage: 'render:*:*'