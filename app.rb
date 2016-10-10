require 'rubygems'

require 'rack'
require 'sinatra'
require 'sinatra/json'

require 'dropbox_sdk'

require 'redcarpet'
require 'rouge'
require 'rouge/plugins/redcarpet'

require 'sinatra/reloader' if development?

# ------------------- 設定読み込み
# 基本的にdokku前提なので全てENVから設定は読む(設定ファイルを使わない)

APP_BASE_URL = ENV['APP_BASE_URL'] || 'http://localhost:4567'
APP_TITLE = ENV['APP_TITLE'] || 'GauWriter'

DROPBOX_ACCESS_TYPE = :app_folder

DROPBOX_APP_KEY = ENV['DROPBOX_APP_KEY']
DROPBOX_APP_SECRET = ENV['DROPBOX_APP_SECRET']

DROPBOX_REQUEST_TOKEN_KEY = ENV['DROPBOX_REQUEST_TOKEN_KEY']
DROPBOX_REQUEST_TOKEN_SECRET = ENV['DROPBOX_REQUEST_TOKEN_SECRET']

DROPBOX_ACCESS_TOKEN_KEY = ENV['DROPBOX_ACCESS_TOKEN_KEY']
DROPBOX_ACCESS_TOKEN_SECRET = ENV['DROPBOX_ACCESS_TOKEN_SECRET']


# ------------------- クラス拡張

class DropboxClient
  def get_metadata_if_exists(path)
    result = self.metadata(path)
    return result
  rescue DropboxError
    return nil
  end
end

class HTMLWithCodeHighlight < Redcarpet::Render::HTML
  include Rouge::Plugins::Redcarpet
end

# ------------------- ヘルパー

helpers do
  def create_dropbox_client
    session = DropboxSession.new(DROPBOX_APP_KEY, DROPBOX_APP_SECRET)
    session.set_request_token(DROPBOX_REQUEST_TOKEN_KEY, DROPBOX_REQUEST_TOKEN_SECRET)
    session.set_access_token(DROPBOX_ACCESS_TOKEN_KEY, DROPBOX_ACCESS_TOKEN_SECRET)
    DropboxClient.new(session, DROPBOX_ACCESS_TYPE)
  end

  def send_dropbox_file(path, opts = {})
    client = create_dropbox_client

    raw, metadata = client.get_file_and_metadata(path)

    last_modified Time.parse(metadata['modified'])
    if opts[:type] or not response['Content-Type']
      content_type opts[:type] || File.extname(path), :default => 'application/octet-stream'
    end

    headers['Content-Length'] ||= raw.length
    opts[:status] = Integer(opts.fetch(:status, 200))
    halt opts[:status], raw
  rescue DropboxError
    not_found
  end

  def render_dropbox_markdown(path, opts = {})
    dirname = File.dirname(path)
    basename = File.basename(path, '.md')

    client = create_dropbox_client

    metadata = client.get_metadata_if_exists(path)
    if metadata && metadata['is_dir']
      entry = client.metadata("#{dirname}/#{basename}/index.md")
    elsif /\/$/ !~ path
      entry = client.metadata("#{dirname}/#{basename}.md")
    end

    not_found unless entry
    not_found if entry['is_dir']

    raw = client.get_file(entry['path'])
    raw.force_encoding 'utf-8'

    processor = Redcarpet::Markdown.new(HTMLWithCodeHighlight, fenced_code_blocks: true, autolink: true, tables: true)
    rendered = processor.render(raw)
    @title = APP_TITLE
    @title = "#{APP_TITLE} :: #{path}" if path == '/'
    @body = rendered
    erb :md
  rescue DropboxError
    not_found
  end
end

# ------------------- API実装

not_found do
  'Not found'
end

get '/*' do |path|
  extname = File.extname(path)

  unless extname == '' || extname == '.md'
    send_dropbox_file path
  else
    render_dropbox_markdown path
  end
end

# ------------------- 生存チェック用
get '/ping' do
  'running!'
end
