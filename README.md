[vimeo-downloader](https://github.com/epicsf/vimeo-downloader)
================================================================================

A Ruby script for downloading a backup of your published Vimeo videos, suitable
for re-uploading to another video service provider.

The first time you run it, it will download all your video metadata and output
to a CSV file. If that looks good, run the script again passing the
`--download` flag to actually start downloading.

Setup
-----

1. Install dependencies (`bundle install`). The script uses
   [youtube-dl](https://github.com/rg3/youtube-dl) to do the heavy lifting,
   so you'll also need that (`brew install youtube-dl`).

2. Generate an access token for your Vimeo account
   ([https://developer.vimeo.com](https://developer.vimeo.com)). You can either
   store this in an `.auth_token` file in the project directory or supply it as
   a command line argument to the script (see below).

Usage
-----

Run `vimeo-downloader.rb`, supplying your all the required credentials: the
auth token for your vimeo account, vimeo account username, email, and password
(required for logging in to download original video files):

    ruby vimeo-downloader.rb \
      --auth-token abc123 \
      --username epicsf \
      --email epicsf@example.com \
      --password yoursecretpassword

You can optionally supply the auth token value in a file named `.auth_token`
and the Vimeo account username/password in a `.netrc` file (see
[instructions for youtube-dl](https://github.com/rg3/youtube-dl/#authentication-with-netrc-file).)

Here are all the available options or flags you can set:

    Usage: vimeo-downloader [options]
        -a, --auth-token TOKEN           Vimeo account auth token
        -u, --username NAME              Vimeo account username
        -e, --email EMAIL                Vimeo account email (or supply in .netrc)
        -p, --password PASSWORD          Vimeo account password (or supply in .netrc)
        -l, --limit COUNT                Fetch count limit (for testing)
        -d, --download                   Download video files
        -o, --output PATH                Path for output files
