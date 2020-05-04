Rename the media file name to shooting date
====

## Overview

This tool renames the file/directory name on the shooting date of the meta information included in the photo/video.
In the default mode, only rename the file name.

## Requirement

The following modules are required.

    File::Copy 'move'
    Getopt::Long 'GetOptions'
    Image::ExifTool
    Text::CharWidth 'mbswidth'

## Usage

  rename_by_meta.pl [OPTIONS] <directory> 
 
    OPTIONS: 
      -h, --help         : this message. 
      -d, --dry-run      : print result, but not execute rename.
      -r, --rename-dir   : rename directory, too.
      -y, --yes          : always yes. 

## Installation

Unnecessary.

## Licence

[MIT](https://github.com/isuka/C2Flow/blob/master/LICENCE)

## Author

[isuka](https://github.com/isuka)
