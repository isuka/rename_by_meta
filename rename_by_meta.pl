#!/usr/bin/perl

use utf8;
use strict;
use warnings;

use File::Copy 'move';
use Getopt::Long 'GetOptions';
use Image::ExifTool;
use Text::CharWidth 'mbswidth';

#use Data::Dumper::AutoEncode;

# OBJECTS
#   %path_stack {
#     'type' => 'directory'
#     'path' => folder path list
#     'start' => first shooting date in 'item'(work data for 'directory_to')
#     'end'   => last shooting date in 'item'(work data for 'directory_to')
#     'directory_to' => rename directory name
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

# command options
my $help;
my $dry_run;
my $insert;
my $rename_dir;
my $yes;

sub main
{
    GetOptions(
        'help' => \$help,
        'dry-run' => \$dry_run,
        'insert' => \$insert,
        'rename-dir' => \$rename_dir,
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
        if ($rename_dir) {
            &check_directorys($stack);
        }

        # リネーム予定を表示
        &display_rename_files($stack);
        if ($rename_dir) {
            &display_rename_directorys($stack);
        }

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
            if ($rename_dir) {
                &rename_directorys($stack);
            }
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
        if (defined($item->{'file_to'}) && $insert) {
            $item->{'file_to'} .= '_' . $item->{'file_from'};
            $item->{'file_to'} =~ s/\.[^\.]+$//; # rename時に拡張子を付与するので削除しておく
        }
    }
}

sub check_directorys
{
    my $stack = shift;
    my $path_len = shift;
    my $items = $stack->{'item'};
    $stack->{'start'} = '99991231';
    $stack->{'end'} = '00000101';

    foreach my $item (@$items) {
        if ($item->{'type'} eq 'directory') {
            &check_directorys($item, $path_len);
            $stack->{'start'} = $item->{'start'} < $stack->{'start'} ? $item->{'start'} : $stack->{'start'};
            $stack->{'end'}   = $item->{'end'} > $stack->{'end'} ? $item->{'end'} : $stack->{'end'};
        } elsif ($item->{'type'} eq 'file') {
            if (!defined($item->{'file_to'})) { next; }
            # ファイル名から日付け情報を取得
            my $date = $item->{'file_to'};
            $date =~ s/_.*$//;
            $date =~ s/-//g;
            $stack->{'start'} = $date < $stack->{'start'} ? $date : $stack->{'start'};
            $stack->{'end'} = $date > $stack->{'end'} ? $date : $stack->{'end'};
        }
    }

    
    my $path = &array2path($stack->{'path'});
    my $dir = ${$stack->{'path'}}[$#{$stack->{'path'}}];
    if ($path =~ s/\/[^\/]+$/\//) {
        $dir =~ s/^\d+-\d+_*//; # pathに日付け情報が含まれている場合は削除
        $stack->{'directory_to'} = $path . $stack->{'start'} . '-' . $stack->{'end'} . '_' . $dir;
    } else {
        $stack->{'directory_to'} = $dir;
    }
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
sub display_rename_files
{
    my $stack = shift;
    my $path_len = &get_max_path_len($stack);
    my $from_len = &get_max_from_len($stack);

    $path_len *= -1; # 左寄せのため負数にする
    $from_len *= -1; # 左寄せのため負数にする
    print("---- RENAME FILES ----\n");
    printf("%*s  %*s  %s\n", $path_len, 'PATH', $from_len, 'FROM', 'TO');
    &disp_rename_files($stack, $path_len, $from_len);
    print("\n");

    print("---- NOT RENAME FILES ----\n");
    printf("%*s  %*s\n", $path_len, 'PATH', $from_len, 'FROM');
    &disp_not_rename_files($stack, $path_len, $from_len);
    print("\n");
}

sub display_rename_directorys
{
    my $stack = shift;
    my $path_len = &get_max_path_len($stack);

    $path_len *= -1; # 左寄せのため負数にする

    print("---- RENAME DIRECTORYS ----\n");
    printf("%*s  %s\n", $path_len, 'FROM', 'TO');
    &disp_rename_directorys($stack, $path_len);
    print("\n");
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
# display rename files/directorys
#
#   INPUT  : files(ref)
#   OUTPUT : -
sub disp_rename_files
{
    my $stack = shift;
    my $path_len = shift;
    my $from_len = shift;
    my $items = $stack->{'item'};
    my $path = &array2path($stack->{'path'});

    foreach my $item (@$items) {
        if ($item->{'type'} eq 'directory') {
            &disp_rename_files($item, $path_len, $from_len);
        } elsif ($item->{'type'} eq 'file') {
            if (!defined($item->{'file_to'})) { next; }
            printf("%*s  %*s  %s.%s\n",
                   $path_len, $path,
                   $from_len, $item->{'file_from'},
                   $item->{'file_to'}, $item->{'extention'});
        }
    }
}

sub disp_not_rename_files
{
    my $stack = shift;
    my $path_len = shift;
    my $from_len = shift;
    my $items = $stack->{'item'};
    my $path = &array2path($stack->{'path'});

    foreach my $item (@$items) {
        if ($item->{'type'} eq 'directory') {
            &disp_not_rename_files($item, $path_len, $from_len);
        } elsif ($item->{'type'} eq 'file') {
            if (defined($item->{'file_to'})) { next; }
            printf("%*s  %*s\n",
                   $path_len, $path,
                   $from_len, $item->{'file_from'});
        }
    }
}

sub disp_rename_directorys
{
    my $stack = shift;
    my $path_len = shift;
    my $items = $stack->{'item'};
    my $path = &array2path($stack->{'path'});
    $stack->{'start'} = '99991231';
    $stack->{'end'} = '00000101';

    foreach my $item (@$items) {
        if ($item->{'type'} eq 'directory') {
            &disp_rename_directorys($item, $path_len);
        }
    }

    printf("%*s %s\n", $path_len, $path, $stack->{'directory_to'});
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
            print("file move: $from -> $to\n");
            move($from, $to) or die "[ERROR] can't move: $from -> $to\n";
        }
    }
}

sub rename_directorys
{
    my $stack = shift;
    my $items = $stack->{'item'};
    my $path = &array2path($stack->{'path'});

    foreach my $item (@$items) {
        if ($item->{'type'} eq 'directory') {
            &rename_directorys($item);
        }
    }

    my $from = $path;
    my $to   = $stack->{'directory_to'};
    print("directory move: $from -> $to\n");
    move($from, $to) or die "[ERROR] can't move: $from -> $to\n";
}

exit 0;
