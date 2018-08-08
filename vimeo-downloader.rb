require 'rubygems'
require 'bundler/setup'
require 'optparse'
require 'vimeo_me2'

VimeoAccountInfo = Struct.new(:auth_token, :username, :limit)
account_info = VimeoAccountInfo.new

OptionParser.new do |opts|
  opts.on('-a', '--auth-token TOKEN', String, 'Vimeo account auth token') do |auth_token|
    account_info.auth_token = auth_token
  end
  opts.on('-u', '--username NAME', String, 'Vimeo account username') do |username|
    account_info.username = username
  end
  opts.on('-l', '--limit COUNT', OptionParser::DecimalInteger, 'Fetch count limit (for testing)') do |limit|
    account_info.limit = limit
  end
end.parse!

account_info.auth_token ||= File.exist?('.auth_token') && File.read('.auth_token').chomp

vimeo = VimeoMe2::VimeoObject.new(account_info.auth_token)
vimeo_user = VimeoMe2::User.new(account_info.auth_token, account_info.username)
user = OpenStruct.new(vimeo_user.user)
video_count = user.metadata['connections']['videos']['total']

puts %{Starting export for "#{user.name}" (#{account_info.username})}
puts %{Exporting metadata for #{video_count} videos #{"(limiting to #{account_info.limit})" if account_info.limit}}

output_directory_name = 'output'
Dir.mkdir(output_directory_name) unless File.exists?(output_directory_name)

csv_filename = "vimeo_export_#{account_info.username}_#{Time.now.iso8601.gsub(':', '')}.csv"
csv_file_path = File.join(output_directory_name, csv_filename)
csv_counter = 0
csv_headers = %w(
  uri
  name
  description
  link
  duration
  created_time
  release_time
  view_privacy
  tags
  play_stats
  status
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
        v.name,
        v.description || '', # allowed to be nil
        v.link,
        v.duration,
        v.created_time,
        v.release_time,
        v.privacy['view'],
        v.tags.map { |t| t['name'] }.join(','),
        v.stats['plays'],
        v.status
      ]

      raise "CSV row has non-string values" unless row.all? { |v| v.is_a?(String) || v.is_a?(Numeric) }
      raise "CSV row columns don't match headers" if row.length != csv_headers.length

      csv << row
      csv_counter += 1
      puts %{Processed #{csv_counter.to_s.rjust(video_count.digits.count, '0')}/#{video_count} (#{(csv_counter/video_count.to_f * 100).to_i}%) "#{v.name}"}
    end

    next_page = vidoes_page['paging']['next']

    break if account_info.limit && csv_counter >= account_info.limit
  end
end

puts "Finished downloading metadata for #{csv_counter} videos"
