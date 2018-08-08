[vimeo-downloader](https://github.com/epicsf/vimeo-downloader)
================================================================================

A Ruby script for downloading an archive of published Vimeo videos, suitable
for re-uploading to another video service provider.

In its current iteration, it simply outputs a CSV of video metadata and actually downloading video files is left as an exercise for the reader…

Setup
-----

1. Install dependencies (`bundle install`)

2. Generate an access token for your Vimeo account
   ([https://developer.vimeo.com](https://developer.vimeo.com)). You can either
   store this in an `.auth_token` file in the project directory or supply it as
   a command line argument to the script (see below).

Usage
-----

Run `vimeo-downloader.rb`, supplying your auth token and the vimeo account
username you'd like to download:

   ruby vimeo-downloader.rb --auth-token abc123 --username epicsf

You can optionally supply the auth token value in a file named `.auth_token`.
You can also limit the number of videos it downloads by setting a `--limit NUM`
flag, e.g. for testing on a smaller number of videos.

To-Do
-----

Actually download video files.
