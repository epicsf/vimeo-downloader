require 'rubygems'
require 'bundler/setup'
require 'optparse'
require 'vimeo_me2'

Video = Struct.new(:uri, :name, :description, :link, :duration, :created_time, :release_time, :view_privacy, :tags, :play_stats, :status, keyword_init: true) do
  def validate!
    nil_allowed = [:description]
    each_pair do |k, v|
      next if v.nil? && nil_allowed.include?(k)
      unless v.is_a?(String) || v.is_a?(Numeric)
        raise "Video has non-stringable attribute value (#{k}): #{v}"
      end
    end
    true
  end
end

videos = []

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
vimeo_video_count = user.metadata['connections']['videos']['total']

puts %{Starting export for "#{user.name}" (#{account_info.username})}
puts %{Exporting metadata for #{vimeo_video_count} videos #{"(limiting to #{account_info.limit})" if account_info.limit}}

output_directory_name = 'output'
Dir.mkdir(output_directory_name) unless File.exists?(output_directory_name)

csv_filename = "vimeo_export_#{account_info.username}_#{Time.now.iso8601.gsub(':', '')}.csv"
csv_file_path = File.join(output_directory_name, csv_filename)

puts "Writing CSV at #{csv_file_path}…"

CSV.open(csv_file_path, 'wb') do |csv|

  # write headers
  csv << Video.members

  # start downloading video list pages
  next_page = vimeo_user.get_video_list['paging']['first']
  while next_page
    vidoes_page = vimeo.get(next_page)

    # write a row for each video in this page
    vidoes_page['data'].each do |video_data|
      video = Video.new(
        uri:             video_data['uri'],
        name:            video_data['name'],
        description:     video_data['description'],
        link:            video_data['link'],
        duration:        video_data['duration'],
        created_time:    video_data['created_time'],
        release_time:    video_data['release_time'],
        view_privacy:    video_data['privacy']['view'],
        tags:            video_data['tags'].map { |t| t['name'] }.join(','),
        play_stats:      video_data['stats']['plays'],
        status:          video_data['status']
      )

      video.validate!
      videos << video
      csv << video.to_a

      progress_string = "#{videos.count.to_s.rjust(vimeo_video_count.digits.count, '0')}/#{vimeo_video_count} (#{(videos.count/vimeo_video_count.to_f * 100).to_i}%) "
      puts %{Processed #{progress_string}"#{video.name}"}
    end

    next_page = vidoes_page['paging']['next']

    break if account_info.limit && videos.count >= account_info.limit
  end
end

puts "Finished downloading metadata for #{videos.count} videos"
