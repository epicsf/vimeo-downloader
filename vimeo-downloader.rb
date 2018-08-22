require 'rubygems'
require 'bundler/setup'
require 'optparse'
require 'fileutils'
require 'active_support/time'
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

  def upload_date
    # Need to convert time zones because created_time is in UTC, but youtube-dl
    # upload_date seems to be in Vimeo-local time which is NYC.
    tz = ActiveSupport::TimeZone['US/Eastern']
    Time.parse(created_time).in_time_zone(tz).strftime('%Y%m%d')
  end

  def id
    uri.split('/').last
  end
end

videos = []

Options = Struct.new(:auth_token, :username, :email, :password, :limit, :download, :output_path)
options = Options.new

OptionParser.new do |opts|
  opts.on('-a', '--auth-token TOKEN', String, 'Vimeo account auth token') do |auth_token|
    options.auth_token = auth_token
  end
  opts.on('-u', '--username NAME', String, 'Vimeo account username') do |username|
    options.username = username
  end
  opts.on('-e', '--email EMAIL', String, 'Vimeo account email (or supply in .netrc)') do |email|
    options.email = email
  end
  opts.on('-p', '--password PASSWORD', String, 'Vimeo account password (or supply in .netrc)') do |password|
    options.password = password
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

output_directory_name = File.expand_path(options.username, options.output_path)
FileUtils.mkpath(output_directory_name) unless File.exists?(output_directory_name)

base_filename = "vimeo_export_#{options.username}_#{Time.now.iso8601.gsub(':', '')}"
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

DownloadResult = Struct.new(:url, :status)
download_results = []

Signal.trap('INT') { throw :sigint }
catch :sigint do
  videos.each do |video|

    completion_flag_path = "#{output_directory_name}/videos/#{video.upload_date}-#{video.id}/.complete"

    # Skip already downloaded
    if File.exist? completion_flag_path
      download_results << DownloadResult.new(video.link, :skipped)
      puts "Already downloaded, skipping: #{video.link}"
      next
    end

    # Build youtube-dl command
    download_command = 'youtube-dl'
    download_args = Array.new.tap do |a|
      a << 'ignore-config'         # ignore any local config and use only this one
      a << 'no-overwrites'         # don't overwrite already-downloaded files
      a << 'write-description'     # output a text file with video description
      a << 'write-info-json'       # output a JSON file with video metadata (redundant with CSV data but why not)
      a << 'write-thumbnail'       # output a thumbnail image file
      a << 'format Original'       # only download original source file

      # auth from passed username/password or ~/.netrc file
      if options.username && options.password
        a << "username #{options.email}"
        a << "password #{options.password}"
      else
        a << 'netrc'
      end

      a << "output '#{output_directory_name}/videos/%(upload_date)s-%(id)s/%(id)s.%(ext)s'"
    end

    # Append all the above arguments/flags
    download_args.each do |arg|
      download_command << " \\\n  --#{arg}"
    end

    # Append video URL
    download_command << " \\\n  #{video.link}"

    # Download and collect result
    puts "Executing:\n#{download_command.strip}"
    success = system(download_command)

    FileUtils.touch(completion_flag_path) if success

    download_results << DownloadResult.new(video.link, success)
  end
end

successes, failures = download_results.partition { |r| !!r.status }

puts "\n\n"
puts "Download results:"
puts "Unfinished: #{videos.count - download_results.count}"
puts "Success:    #{successes.count}"
puts "Skipped:    #{successes.select { |r| r.status == :skipped }.count}"
puts "Failures:   #{failures.count}"

failures.each do |result|
  puts "  #{result.url}"
end
