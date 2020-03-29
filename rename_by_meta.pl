#!/usr/bin/perl

use utf8;
use strict;
use warnings;

use File::Copy 'move';
use Getopt::Long 'GetOptions';
use Image::ExifTool;

#use Data::Dumper::AutoEncode;

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
        my $files = &get_files($path);

        # ファイルタイプとプロパティチェック
        my $obj = &check_files($files);

        # リネーム予定を表示
        &display_rename($obj);

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
            &rename_files($obj);
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
    $glob_path =~ s/ /\\ /g;
    my @list = glob "$glob_path/*";

    my @files;
    foreach (@list) {
        my $obj;
        $obj->{'path'} = $path;
        if (-d $_) {
            my $ref = &get_files($_);
            push(@files, @$ref);
        } else {
            $_ =~ s/\Q$path\E\///;
            $obj->{'file_from'} = $_;
            push(@files, $obj);
        }
    }

    return \@files;
}

################################################################################
# check files
#
#   INPUT  : files(ref)
#   OUTPUT : file object
sub check_files
{
    my $files = shift;
    my $obj;

    foreach my $file (@$files) {
        $file->{'file_to'} = undef;
        # ファイルの拡張子チェック
        if ($file->{'file_from'} =~ /\.jp[e]*g$/i) {
            $file->{'type'} = 'jpg';
        } elsif ($file->{'file_from'} =~ /\.mp4$/i) {
            $file->{'type'} = 'mp4';
        } elsif ($file->{'file_from'} =~ /\.m4v$/i) {
            $file->{'type'} = 'm4v';
        } elsif ($file->{'file_from'} =~ /\.mov$/i) {
            $file->{'type'} = 'mov';
        } else {
            $file->{'type'} = undef;
            next;
        }
        &make_file_name($file);
        push(@$obj, $file);
    }

    return $obj;
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
    $obj->{'file_to'} = undef;
    my $file = $obj->{'path'} . '/' . $obj->{'file_from'};

    if (!defined($obj->{'type'})) {
        die "[ERROR] file type is undefined. : " . $file;
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
    my $obj = shift;

    # fromの最長文字列を調査
    my $path_len = 0;
    my $from_len = 0;
    foreach my $file (@$obj) {
        my $len = length($file->{'file_from'});
        if ($len > $from_len) { $from_len = $len; }
        $len = length($file->{'path'});
        if ($len > $path_len) { $path_len = $len; }
    }

    $path_len *= -1;
    $from_len *= -1;
    print("---- RENAME FILES ----\n");
    printf("%*s  %*s  %s\n", $path_len, 'PATH', $from_len, 'FROM', 'TO');
    foreach my $file (@$obj) {
        if (!defined($file->{'file_to'})) { next; }
        printf("%*s  %*s  %s.%s\n",
               $path_len, $file->{'path'},
               $from_len, $file->{'file_from'},
               $file->{'file_to'}, $file->{'type'});
    }
    print("\n");

    print("---- NOT RENAME FILES ----\n");
    printf("%*s  %*s\n", $path_len, 'PATH', $from_len, 'FROM');
    foreach my $file (@$obj) {
        if (defined($file->{'file_to'})) { next; }
        printf("%*s  %*s\n",
               $path_len, $file->{'path'},
               $from_len, $file->{'file_from'});
    }
    print("\n");

    return;
}

################################################################################
# rename files
#
#   INPUT  : files(ref)
#   OUTPUT : -
sub rename_files
{
    my $obj = shift;

    foreach my $file (@$obj) {
        if (!defined($file->{'file_to'})) { next; }
        my $from = $file->{'path'} . '/' . $file->{'file_from'};
        my $to   = $file->{'path'} . '/' . $file->{'file_to'} . '.' . $file->{'type'};
        print("move: $from -> $to\n");
        move($from, $to) or die "[ERROR] can't move: $from -> $to\n";
    }
}

exit 0;
