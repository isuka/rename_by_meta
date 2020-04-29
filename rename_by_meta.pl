#!/usr/bin/perl

use utf8;
use strict;
use warnings;

use File::Copy 'move';
use Getopt::Long 'GetOptions';
use Image::ExifTool;
use Text::CharWidth 'mbswidth';

use Data::Dumper::AutoEncode;

# OBJECTS
#   %path_stack {
#     'type' => 'directory'
#     'path' => folder path list
#     'item' => file or directory list
#                 file      : file object
#                 directory : path stack
#   }
#
#   %file_object {
#     'type' => 'file'
#     'extention' => file extention: jpg, mp4, m4v, or mov
#     'file_from' => original file name
#     'file_to' => rename file name
#   }

exit &main();

sub main
{
    my $help;
    my $dry_run;
    my $yes;

    GetOptions(
        'help' => \$help,
        'dry-run' => \$dry_run,
        'yes' => \$yes,
        );
    my $path = shift(@ARGV);

    if ($help) {
        &help();
    } else {
        if (!defined($path)) {
            &help();
            die "[ERROR] path is not defined.\n";
        }

        # 引数で指定されたディレクトリ配下のファイルパス取得
        my $stack = &get_files($path);

        # ファイルタイプとプロパティチェック
        &check_items($stack);

        # リネーム予定を表示
        &display_rename($stack);

        # ファイルごとにリネーム処理
        if ($dry_run) {
            print("dry-run: file not renamed.\n");
        } else {
            if ($yes) {
                print("yes: skip prompt.\n");
            } else {
                print("rename ok?[y/n]\n");
                my $line = <STDIN>;
                if ($line !~ /^y/i) {
                    print("rename stop.\n");
                    return 0;
                }
            }
            &rename_files($stack);
        }
    }

    return 0;
}

################################################################################
# help
#
#   INPUT  : -
#   OUTPUT : -
sub help
{
    my $text = << "EOS";
NAME:
  $0
  rename files by meta-infomation

SYNOPSIS:
  $0 [OPTIONS] <directory>

OPTIONS:
  -h, --help         : this message.
  -d, --dry-run      : print result, but not execute rename.
  -y, --yes          : always yes.
EOS

    print $text . "\n";
    return;
}

################################################################################
# get file paths
#
#   INPUT  : directory path from @ARGV
#   OUTPUT : file paths
sub get_files
{
    my $path = shift;

    # TODO: 引数がディレクトリなのかファイルなのか判定

    $path =~ s/\/$//; # remove notation fluctuation

    my $glob_path = $path;
    $glob_path =~ s/(\s)/\\$1/g;
    my @list = glob "$glob_path/*";

    my @item;
    my $path_stack = {
        'type' => 'directory',
        'path' => &path2array($path),
        'item' => \@item,
        };
    foreach (@list) {
        if (-d $_) {
            push(@item, &get_files($_));
        } else {
            my $file_obj = {
                'type' => 'file',
            };
            $_ =~ s/\Q$path\E\///;
            $file_obj->{'file_from'} = $_;
            push(@item, $file_obj);
        }
    }

    return $path_stack;
}

################################################################################
# path(str) to array reference
#
#   INPUT  : path
#   OUTPUT : directory list reference
sub path2array
{
    my $path = shift;
    my @split = split(/\//, $path);
    return \@split;
}

################################################################################
# array reference to path(str)
#
#   INPUT  : directory list reference
#   OUTPUT : path
sub array2path
{
    my $array = shift;
    return join('/', @$array);
}

################################################################################
# check files
#
#   INPUT  : files(ref)
#   OUTPUT : file object
sub check_items
{
    my $stack = shift;
    my $items = $stack->{'item'};
    my $path = &array2path($stack->{'path'});

    foreach my $item (@$items) {
        if ($item->{'type'} eq 'directory') {
            &check_items($item);
            next;
        } elsif ($item->{'type'} ne 'file') {
            die "[ERROR] undefined stack type. : " . $item->{'type'};
        }

        $item->{'file_to'} = undef;
        # ファイルの拡張子チェック
        if ($item->{'file_from'} =~ /\.jp[e]*g$/i) {
            $item->{'extention'} = 'jpg';
        } elsif ($item->{'file_from'} =~ /\.mp4$/i) {
            $item->{'extention'} = 'mp4';
        } elsif ($item->{'file_from'} =~ /\.m4v$/i) {
            $item->{'extention'} = 'm4v';
        } elsif ($item->{'file_from'} =~ /\.mov$/i) {
            $item->{'extention'} = 'mov';
        } else {
            $item->{'extention'} = undef;
            next;
        }
        &make_file_name($item, $path);
    }

    return;
}

################################################################################
# make file name
#   get exif and generate file name
#
#   INPUT  : files object
#   OUTPUT : -
sub make_file_name
{
    my $obj = shift;
    my $path = shift;
    $obj->{'file_to'} = undef;
    my $file = $path . '/' . $obj->{'file_from'};

    if (!defined($obj->{'extention'})) {
        die "[ERROR] file extention is undefined. : " . $file;
    }

    my $exif = &get_exif($file);
    if (!defined($exif)) { return; }

    $obj->{'file_to'} = &dto2fname($exif);
    if (defined($obj->{'file_to'})) { return; }
    $obj->{'file_to'} = &mcd2fname($exif);
    if (defined($obj->{'file_to'})) { return; }

    return;
}

################################################################################
# get Exif
#
#   INPUT  : jpeg file name
#   OUTPUT : Exif object
sub get_exif
{
    my $file = shift;
    my $exiftool = new Image::ExifTool;
    my $exifinfo = $exiftool->ImageInfo($file);
    return $exifinfo;
}

################################################################################
# convert Exif(DateTimeOriginal) to File Name
#
#   INPUT  : Exif object
#   OUTPUT : formatted file name
sub dto2fname
{
    my $exif = shift;

    # 撮影日時情報があるかチェック
    if (!defined($exif->{'DateTimeOriginal'})) {
        return undef;
    }

    my $date = $exif->{'DateTimeOriginal'};
    $date =~ s/:/-/g;
    $date =~ s/ /_/g;

    return $date;
}

################################################################################
# convert Exif(MediaCreateDate) to File Name
#
#   INPUT  : Exif object
#   OUTPUT : formatted file name
sub mcd2fname
{
    my $exif = shift;

    # 撮影日時情報があるかチェック
    if (!defined($exif->{'MediaCreateDate'})) {
        return undef;
    }

    my $date = $exif->{'MediaCreateDate'};
    $date =~ s/:/-/g;
    $date =~ s/ /_/g;

    return $date;
}

################################################################################
# display rename
#
#   INPUT  : file object
#   OUTPUT : -
sub display_rename
{
    my $stack = shift;
    my $obj; # DEBUG

    # fromの最長文字列を調査
    my $path_len = &get_max_path_len($stack);
    my $from_len = &get_max_from_len($stack);

    $path_len *= -1; # 左寄せのため負数にする
    $from_len *= -1; # 左寄せのため負数にする
    print("---- RENAME FILES ----\n");
    printf("%*s  %*s  %s\n", $path_len, 'PATH', $from_len, 'FROM', 'TO');
    &display_rename_files($stack, $path_len, $from_len);
    print("\n");

    print("---- NOT RENAME FILES ----\n");
    printf("%*s  %*s\n", $path_len, 'PATH', $from_len, 'FROM');
    &display_not_rename_files($stack, $path_len, $from_len);
    print("\n");

    return;
}

################################################################################
# get max path character length
#
#   INPUT  : files(ref)
#   OUTPUT : character count
sub get_max_path_len
{
    my $stack = shift;
    my $items = $stack->{'item'};
    my $max_len = 0;

    foreach my $item (@$items) {
        if ($item->{'type'} eq 'directory') {
            my $path = &array2path($item->{'path'});
            my $path_len = mbswidth($path);
            $max_len = $path_len > $max_len ? $path_len : $max_len;
            $path_len = &get_max_path_len($item);
            $max_len = $path_len > $max_len ? $path_len : $max_len;
        }
    }

    return $max_len;
}

################################################################################
# get max file name character length
#
#   INPUT  : files(ref)
#   OUTPUT : character count
sub get_max_from_len
{
    my $stack = shift;
    my $items = $stack->{'item'};
    my $max_len = 0;

    foreach my $item (@$items) {
        my $file_len = 0;
        if ($item->{'type'} eq 'directory') {
            $file_len = &get_max_from_len($item);
        } elsif ($item->{'type'} eq 'file') {
            my $file = $item->{'file_from'};
            $file_len = mbswidth($file);
        }
        $max_len = $file_len > $max_len ? $file_len : $max_len;
    }

    return $max_len;
}

################################################################################
# display rename files
#
#   INPUT  : files(ref)
#   OUTPUT : -
sub display_rename_files
{
    my $stack = shift;
    my $path_len = shift;
    my $from_len = shift;
    my $items = $stack->{'item'};
    my $path = &array2path($stack->{'path'});

    foreach my $item (@$items) {
        if ($item->{'type'} eq 'directory') {
            &display_rename_files($item, $path_len, $from_len);
        } elsif ($item->{'type'} eq 'file') {
            if (!defined($item->{'file_to'})) { next; }
            printf("%*s  %*s  %s.%s\n",
                   $path_len, $path,
                   $from_len, $item->{'file_from'},
                   $item->{'file_to'}, $item->{'extention'});
        }
    }
}

sub display_not_rename_files
{
    my $stack = shift;
    my $path_len = shift;
    my $from_len = shift;
    my $items = $stack->{'item'};
    my $path = &array2path($stack->{'path'});

    foreach my $item (@$items) {
        if ($item->{'type'} eq 'directory') {
            &display_not_rename_files($item, $path_len, $from_len);
        } elsif ($item->{'type'} eq 'file') {
            if (defined($item->{'file_to'})) { next; }
            printf("%*s  %*s\n",
                   $path_len, $path,
                   $from_len, $item->{'file_from'});
        }
    }
}

################################################################################
# rename files
#
#   INPUT  : files(ref)
#   OUTPUT : -
sub rename_files
{
    my $stack = shift;
    my $items = $stack->{'item'};
    my $path = &array2path($stack->{'path'});

    foreach my $item (@$items) {
        if ($item->{'type'} eq 'directory') {
            &rename_files($item);
        } elsif ($item->{'type'} eq 'file') {
            if (!defined($item->{'file_to'})) { next; }
            my $from = $path . '/' . $item->{'file_from'};
            my $to   = $path . '/' . $item->{'file_to'} . '.' . $item->{'extention'};
            print("move: $from -> $to\n");
            move($from, $to) or die "[ERROR] can't move: $from -> $to\n";
        }
    }
}

exit 0;
