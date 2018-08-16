require 'rubygems'
require 'bundler/setup'
require 'optparse'
require 'vimeo_me2'

Video = Struct.new(:uri, :name, :description, :link, :duration, :created_time, :release_time, :view_privacy, :download_privacy, :tags, :play_stats, :status, keyword_init: true) do
  def validate!
    nil_allowed = [:description]
    each_pair do |k, v|
      next if v.nil? && nil_allowed.include?(k)
      unless v.is_a?(String) || v.is_a?(Numeric) || v.is_a?(TrueClass) || v.is_a?(FalseClass)
        raise "Video has non-stringable attribute value (#{k}): #{v}"
      end
    end
    true
  end
end

videos = []

Options = Struct.new(:auth_token, :username, :limit, :download, :output_path)
options = Options.new

OptionParser.new do |opts|
  opts.on('-a', '--auth-token TOKEN', String, 'Vimeo account auth token') do |auth_token|
    options.auth_token = auth_token
  end
  opts.on('-u', '--username NAME', String, 'Vimeo account username') do |username|
    options.username = username
  end
  opts.on('-l', '--limit COUNT', OptionParser::DecimalInteger, 'Fetch count limit (for testing)') do |limit|
    options.limit = limit
  end
  opts.on('-d', '--download', 'Download video files') do |download|
    options.download = download
  end
  opts.on('-o', '--output PATH', String, 'Path for output files') do |path|
    options.output_path = path
  end
end.parse!

options.auth_token ||= File.exist?('.auth_token') && File.read('.auth_token').chomp
options.output_path ||= 'output'

vimeo = VimeoMe2::VimeoObject.new(options.auth_token)
vimeo_user = VimeoMe2::User.new(options.auth_token, options.username)
user = OpenStruct.new(vimeo_user.user)
vimeo_video_count = user.metadata['connections']['videos']['total']

puts %{Starting export for "#{user.name}" (#{options.username})}
puts %{Exporting metadata for #{vimeo_video_count} videos #{"(limiting to #{options.limit})" if options.limit}}

output_directory_name = File.expand_path(options.output_path, options.username)
FileUtils.mkpath(output_directory_name) unless File.exists?(output_directory_name)

base_filename = "vimeo_export_#{options.username}_#{Time.now.iso8601.gsub(':', '')}"
video_urls_file = Tempfile.new(base_filename)
csv_file_path = File.join(output_directory_name, "#{base_filename}.csv")

puts "Writing CSV at #{csv_file_path}…"

CSV.open(csv_file_path, 'wb') do |csv|

  # write headers
  csv << Video.members

  catch :limit_reached do
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
          download_privacy:video_data['privacy']['download'],
          tags:            video_data['tags'].map { |t| t['name'] }.join(','),
          play_stats:      video_data['stats']['plays'],
          status:          video_data['status']
        )

        video.validate!
        videos << video
        csv << video.to_a
        video_urls_file << video.link + "\n"
        video_urls_file.flush

        progress_string = "#{videos.count.to_s.rjust(vimeo_video_count.digits.count, '0')}/#{vimeo_video_count} (#{(videos.count/vimeo_video_count.to_f * 100).to_i}%) "
        puts %{Processed #{progress_string}"#{video.name}"}

        throw :limit_reached if options.limit && videos.count >= options.limit
      end

      next_page = vidoes_page['paging']['next']
    end
  end
end

puts "Finished downloading metadata for #{videos.count} videos"

return unless options.download

puts "\n"
puts "Starting video file downloads…"

has_downloader = !`which youtube-dl`.empty?
abort("\nCouldn't find downloader. Please install youtube-dl first (brew install youtube-dl).") unless has_downloader

download_command = <<-SH
youtube-dl \\
  --abort-on-error \\
  --write-description \\
  --write-info-json \\
  --write-thumbnail \\
  --restrict-filenames \\
  --no-overwrites \\
  --ignore-config \\
  --netrc \\
  --format Original/best \\
  --output '#{output_directory_name}/videos/%(upload_date)s-%(id)s/%(id)s.%(ext)s' \\
  --batch-file #{video_urls_file.path}
SH

puts "Executing:\n#{download_command.strip}"
exec download_command
