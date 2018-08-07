require 'rubygems'
require 'bundler/setup'
require 'optparse'
require 'vimeo_me2'

VimeoAccountInfo = Struct.new(:auth_token, :username)
account_info = VimeoAccountInfo.new

OptionParser.new do |opts|
  opts.on('-a', '--auth-token', 'Vimeo account auth token') do |auth_token|
    account_info.auth_token = auth_token
  end
  opts.on('-u', '--username', 'Vimeo account username') do |username|
    account_info.username = username
  end
end

account_info.auth_token ||= File.read('.auth_token').chomp
account_info.username   ||= File.read('.vimeo_username').chomp

vimeo = VimeoMe2::VimeoObject.new(account_info.auth_token)
vimeo_user = VimeoMe2::User.new(account_info.auth_token, account_info.username)
user = OpenStruct.new(vimeo_user.user)

puts %{Starting export for "#{user.name}" (#{account_info.username})}
puts %{Exporting metadata for #{user.metadata['connections']['videos']['total']} videos}

output_directory_name = 'output'
Dir.mkdir(output_directory_name) unless File.exists?(output_directory_name)

csv_filename = "vimeo_export_#{account_info.username}_#{Time.now.iso8601.gsub(':', '')}.csv"
csv_file_path = File.join(output_directory_name, csv_filename)
csv_counter = 0
csv_headers = %w(
  uri
  name
)

puts "Writing CSV at #{csv_file_path}…"

CSV.open(csv_file_path, 'wb') do |csv|

  # write headers
  csv << csv_headers

  # start downloading video list pages
  next_page = vimeo_user.get_video_list['paging']['first']
  while next_page
    vidoes_page = vimeo.get(next_page)

    # write a row for each video in this page
    vidoes_page['data'].each do |video_data|
      v = OpenStruct.new(video_data)
      row = [
        v.uri,
        v.name
      ]
      raise "CSV row columns don't match headers" if row.length != csv_headers.length
      csv << row
      csv_counter += 1
      puts %{Processed "#{v.name}"}
    end

    next_page = vidoes_page['paging']['next']

    break if csv_counter >= 50
  end
end

puts "Finished downloading metadata for #{csv_counter} videos"
