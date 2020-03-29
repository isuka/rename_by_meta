Rename the media file name to shooting date
====

## Overview

This tool renames the file name on the shooting date of the meta information included in the photo / video.

## Requirement

The following modules are required.

    File::Copy 'move'
    Getopt::Long 'GetOptions'
    Image::ExifTool

## Usage

  rename_by_meta.pl [OPTIONS] <directory> 
 
    OPTIONS: 
      -h, --help         : this message. 
      -d, --dry-run      : print result, but not execute rename. 
      -y, --yes          : always yes. 

## Installation

Unnecessary.

## Licence

[MIT](https://github.com/isuka/C2Flow/blob/master/LICENCE)

## Author

[isuka](https://github.com/isuka)
