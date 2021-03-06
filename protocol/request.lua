--[[
Copyright 2012 Rackspace

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS-IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
--]]

local https = require('https')
local fs = require('fs')

local logging = require('logging')
local Error = require('core').Error
local misc = require('../util/misc')

local dns = require('dns')

local fmt = require('string').format
local Object = require('core').Object

local Request = Object:extend()

--[[
  Attempts to upload or download a file over https to options.host:options.port OR
  for endpoints in options.endpoints.  Will try options.attempts number of times, or
  for each endpoint if not specified.

  options = {
    host/port OR endpoints [{Endpoint1, Endpoint2, ...}]
    path = "string",
    method = "METHOD"
    upload = nil or '/some/path'
    download = nil or '/some/path'
    attempts = int or #endpoints
  }
]]--

local function makeRequest(...)
  local req = Request:new(...)
  req:set_headers()
  req:request()
  return req
end

function Request:initialize(options, callback)
  self.callback = misc.fireOnce(callback)

  if not options.method then
    return self.callback(Error:new('I need a http method'))
  end

  if options.endpoints then
    self.endpoints = misc.merge({}, options.endpoints)
  else
    self.endpoints = {{host=options.host, port=options.port}}
  end

  self.attempts = options.attempts or #self.endpoints
  self.download = options.download
  self.upload = options.upload

  options.endpoints = nil
  options.attempts = nil
  options.download = nil
  options.upload = nil

  self.options = options
  self.active_req_options = nil

  if not self:_cycle_endpoint() then
    return self.callback(Error:new('call with options.port and options.host or options.endpoints'))
  end
end

function Request:request()
  local function run(opts)
    local options = misc.merge({}, self.options, opts)

    -- Save currently active options so we can log it inside _ensure_retries.
    -- Sadly the way the code is currently structured, there is no nicer way to
    -- do it if we want to accurately log the options which were used for the
    -- active request.
    self.active_req_options = options

    logging.debugf('sending request to %s:%s%s', options.host, options.port, options.path)

    local req = https.request(options, function(res)
      self:_handle_response(res)
    end)

    req:on('error', function(err)
      self:_ensure_retries(err)
    end)

    if not self.upload then
      return req:done()
    end

    local data = fs.createReadStream(self.upload)
    data:on('data', function(chunk)
      req:write(chunk)
    end)
    data:on('end', function(d)
      req:done(d)
    end)
    data:on('error', function(err)
      req:done()
      self._ensure_retries(err)
    end)
  end

  if self.endpoint.srv_query then
    dns.resolve(self.endpoint.srv_query, 'SRV', function(err, record)
      if err then return self.callback(err) end
      run({ host = record[1].name, port = record[1].port })
    end)
  else
    run({ host = self.endpoint.host, port = self.endpoint.port })
  end
end

function Request:_cycle_endpoint()
  local position
  if self.attempts == 0 then return false end
  position = #self.endpoints % self.attempts
  self.endpoint = self.endpoints[position+1]
  self.attempts = self.attempts - 1
  return true
end

function Request:set_headers(callback)
  local headers = {}

  -- set defaults
  headers['Content-Length'] = 0
  headers["Content-Type"] = "application/text"
  self.options.headers = misc.merge(headers, self.options.headers)
end

function Request:_write_stream(res)
  logging.debugf('writing stream to disk: %s.', self.download)

  local ok, stream = pcall(function()
    return fs.WriteStream:new(self.download)
  end)

  if not ok then
    -- can't make the file because the dir doens't exist
    if stream.code and stream.code == "ENOENT" then
      return self.callback(stream)
    end
    return self:_ensure_retries(stream, res)
  end

  stream:on('finish', function()
    self:_ensure_retries(nil, res)
  end)

  stream:on('error', function(err)
    self:_ensure_retries(err, res)
  end)

  res:pipe(stream)
end

function Request:_ensure_retries(err, res, buf)
  if not err then
    self.callback(err, res, buf)
    return
  end

  local status = res and res.statusCode or "?"
  local options = self.active_req_options
  local action

  if self.download then
      action = 'download'
  elseif self.upload then
      action = 'upload'
  else
      action = 'request'
  end

  local msg = fmt('%s to %s:%s failed for %s with status: %s and error: %s.', (options.method or "?"),
                  options.host, options.port, (self.download or self.upload or "?"), status, tostring(err))

  logging.warning(msg)

  if not self:_cycle_endpoint() then
    return self.callback(err)
  end

  logging.debugf('retrying %s %d more times.', action, self.attempts)

  self:request()
end

function Request:_handle_response(res)
  if self.download and res.statusCode >= 200 and res.statusCode < 300 then
    return self:_write_stream(res)
  end

  local buf = {}
  res:on('data', function(d)
    table.insert(buf, d)
  end)

  res:on('end', function()
    buf = table.concat(buf)
    if res.statusCode >= 400 then
      return self:_ensure_retries(Error:new(buf), res)
    end
    self:_ensure_retries(nil, res, buf)
  end)
end

exports.makeRequest = makeRequest
exports.Request = Request
