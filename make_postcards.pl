#!/usr/bin/perl
# Copyright 2010 Thomas Lotze
# This script is licensed under a Creative Commons Attribution 3.0 license; you can use it and modify it,
#  so long as you provide an attributuon link to thomaslotze.com  See http://creativecommons.org/licenses/by/3.0/

use strict;
use warnings;
$|=1;  # autoflush output buffers

use POSIX qw(ceil floor);
use File::Path qw(mkpath);
use Getopt::Long;
use File::Basename;

# If you don't have Math::Trig, try this:  perl -MCPAN -e 'install Math::Trig'
use Math::Trig;

##################################################################
# Program inputs
##################################################################

# program control
my $verbose = 0;   # print verbose messages?
my $help=0;        # print help?
# Output folder to hold the images created
my $output_folder = "postcards";

# total width and height (in pixels) for the postcards
my $postcard_width = 638;
my $postcard_height = 825;
# width (in pixels) of the postcard border
my $border_size = 19;
# number of postcard images to create
my $num_images = 20;
# whether to create preview images as well
my $create_previews = 0;
# method for locating postcard centers
my $center_method = "uniform";

GetOptions ('verbose' => \$verbose, 'help'=>\$help,
			'width=i'=>\$postcard_width,
			'height=i'=>\$postcard_height,
			'border=i'=>\$border_size,
			'num_images=i'=>\$num_images,
			'output=s'=>\$output_folder,
			'preview' => \$create_previews,
			'method=s' => \$center_method);

# the input image
my ($input) = @ARGV;;

# An input file is required
if (not($input)) {
	$help = 1;
}

if ($help) {
	my $progname=basename($0);

	print "This program will take an image file and create randomly oriented postcard-sized images from it.\n";
	print "  It also creates printable page-sized images and a composite image of all postcards pasted together.\n";
	print "  It requires ImageMagick, downloadable from http://www.imagemagick.org.\n";
	print "  It also requires Math::Trig, downloadable from http://search.cpan.org/~jhi/Math-Complex-1.56/lib/Math/Trig.pm.\n";
	print "\n";
	print "Basic usage:\n";
	print "$progname <input file>\n";
	print "  creates 20 postcard images, 638x825 (approx quarter-page sized for 8.5\"x11\" at 150 dpi) and puts them in the 'postcards' directory.\n";
	print "\n";
	print "Full usage:\n";
	print "perl $progname <input file>\n";
	print "  --help                     print this help\n";
	print "  --verbose                  run verbosely, with extra informative output\n";
	print "  --width <width>            create postcards <width> pixels wide (default=638)\n";
	print "  --height <height>          create postcards <height> pixels high (default=825)\n";
	print "  --border <border width>    create postcards with a <border width>-pixel white border (default=19)\n";
	print "  --num_images <num_images>  create num_images postcards (default=20)\n";
	print "  --output <output folder>   put output in the <output_folder> directory (default='postcards')\n";
	print "  --method <method>          use <method> to determine postcard locations (default='uniform'); options are 'uniform' and 'circle'\n";
	print "  --preview                  in addition to creating postcard and page images, create preview images showing the area for each postcard to be created\n";
	print "\n";
	print "Examples:\n";
	print "perl $progname --border 0 original.jpg\n";
	print "  creates 20 postcard images from original.jpg, with no border, and puts them in the 'postcards' directory.\n";
	print "perl $progname --verbose --num_images 8 --preview original.jpg\n";
	print "  creates 8 postcard images from original.jpg, with preview images, and puts them in the 'postcards' directory.\n";
	print "perl $progname --method circle --verbose --num_images 40 noisebridge.png\n";
	print "  creates 40 postcard images from noisebridge.png, using the 'circle' method, and puts them in the 'postcards' directory.\n";
	print "\n";
	exit(0);
}


# Helper functions for using imagemagick

sub circle_string {
	my ($x,$y,$r) = @_;
	return("-draw \"circle $x,$y " . ($x+$r) . ",$y\" ");
}

sub image_size {
	my ($image_file) = @_;
	my $dimension_line = `identify $image_file`;
	my ($width, $height) = (0,0);
	if ($dimension_line =~ /(\d+)x(\d+)/) {
		($width, $height) = ($1,$2);
	}
	return($width, $height);
}

sub enact {
	my ($command) = @_;
	if ($verbose) {
		print($command . "\n");
	}
	system($command);
}

sub make_postcards {
	my ($input,$postcard_width,$postcard_height,$border_size,$num_images,$output_folder,$include_postcard_preview,$center_method) = @_;
	if (not($output_folder)) {
		$output_folder = ".";
	}
	my $postcard_folder = "${output_folder}/postcards";
	mkpath($postcard_folder);
	my $preview_folder = "${output_folder}/preview";
	mkpath($preview_folder);

	my ($original_width, $original_height) = image_size($input);

	# get dimensions of the image to be put in the postcard
	my $image_width = $postcard_width - $border_size*2;
	my $image_height = $postcard_height - $border_size*2;

	my $mid_postcard_width = $postcard_width/2;
	my $mid_postcard_height = $postcard_height/2;
	my $mid_image_width = $mid_postcard_width - $border_size;
	my $mid_image_height = $mid_postcard_height - $border_size;

	# Calculations for composite image
	# Add additional transparent border (to display the postcard white border extra)
	my $spillover_border = $postcard_width;
	if ($postcard_height > $postcard_width) {
		$spillover_border = $postcard_height;
	}
	$spillover_border = $spillover_border + $border_size * sqrt(2);
	my $composite_height = $original_height + 2*$spillover_border;
	my $composite_width = $original_width + 2*$spillover_border;

	open FILE, ">$output_folder/sizes.txt";

	# TODO: try starting from the middle, greedily covering with random rotations
	# Now: try random rotations and offsets
	foreach my $postcard_id (1..$num_images) {
		# For testing/default
		my $random_x = $original_width/2;
		my $random_y = $original_height/2;
		my $rotate_degrees = 90;

		if ($center_method eq 'circle') {
			# find a random point in the great circle around the center of the image
			my $max_radius = $original_height/2;
			if ($original_width < $original_height) {
				$max_radius = $original_width/2;
			}
			my $random_theta = deg2rad(rand(361));
			my $random_r = rand(floor($max_radius));
			$random_y = floor($random_y + $random_r * sin($random_theta));
			$random_x = floor($random_x + $random_r * cos($random_theta));
			# we only need to rotate up to 90 degrees to get the full range of possible rectangles
			$rotate_degrees = floor(rand(91));
		} else {
			# find a random point in the image to be the center of the postcard
			$random_y = floor(rand($original_height + 1));
			$random_x = floor(rand($original_width + 1));
			# we only need to rotate up to 90 degrees to get the full range of possible rectangles
			$rotate_degrees = floor(rand(91));
		}

		my $rotate_radians = deg2rad($rotate_degrees);

		if ($verbose) {
			print "$postcard_id : $random_x, $random_y, rotate $rotate_degrees\n";
		}
		print FILE "$postcard_id : $random_x, $random_y, rotate $rotate_degrees\n";

		# now create the affine transformations to create the postcard centered here and rotated

		# Do the rotation /counter-clockwise/, so that the area we crop will be as though we
		#  had rotated /it/ clockwise
		my $make_postcard = "convert -virtual-pixel white $input -distort ScaleRotateTranslate \"$random_x,$random_y 1,1 -$rotate_degrees $mid_image_width,$mid_image_height\" -crop \"${image_width}x${image_height}+0+0\" -bordercolor \"#FFFFFF\" -border $border_size";
		enact("${make_postcard} $postcard_folder/postcard_${postcard_id}.png");
		enact("identify $postcard_folder/postcard_${postcard_id}.png");

		# Make a picture of this, placed, for display -- really just for presentation
		my $make_postcard_placed = "convert $postcard_folder/postcard_${postcard_id}.png -virtual-pixel transparent -background transparent -extent ${original_width}x$original_height -distort ScaleRotateTranslate \"$mid_postcard_width,$mid_postcard_height 1,1 $rotate_degrees $random_x,$random_y\"";
		enact("${make_postcard_placed} $preview_folder/postcard_${postcard_id}_placed_unbordered.png");
		enact("identify $preview_folder/postcard_${postcard_id}_placed_unbordered.png");

		# Add additional transparent border (to display the postcard white border extra)
		my $placement_x = $random_x + $spillover_border;
		my $placement_y = $random_y + $spillover_border;
		my $make_postcard_placed_with_border = "convert $postcard_folder/postcard_${postcard_id}.png -virtual-pixel transparent -background transparent -extent ${composite_width}x$composite_height -distort ScaleRotateTranslate \"$mid_postcard_width,$mid_postcard_height 1,1 $rotate_degrees $placement_x,$placement_y\"";
		enact("${make_postcard_placed_with_border} $preview_folder/postcard_${postcard_id}_placed.png");
		enact("identify $preview_folder/postcard_${postcard_id}_placed.png");

		# create an image with the original, but with pixels pasted in to indicate the expected center and corners of the postcard
		if ($include_postcard_preview) {
			my $sin_theta = sin($rotate_radians);
			my $cos_theta = cos($rotate_radians);
			my $topright_x = $random_x+$border_size + $cos_theta*$mid_image_width - $sin_theta*$mid_image_height;
			my $topright_y = $random_y+$border_size + $sin_theta*$mid_image_width + $cos_theta*$mid_image_height;
			my $topleft_x = $random_x+$border_size - $cos_theta*$mid_image_width - $sin_theta*$mid_image_height;
			my $topleft_y = $random_y+$border_size - $sin_theta*$mid_image_width + $cos_theta*$mid_image_height;
			my $bottomright_x = $random_x+$border_size + $cos_theta*$mid_image_width + $sin_theta*$mid_image_height;
			my $bottomright_y = $random_y+$border_size + $sin_theta*$mid_image_width - $cos_theta*$mid_image_height;
			my $bottomleft_x = $random_x+$border_size - $cos_theta*$mid_image_width + $sin_theta*$mid_image_height;
			my $bottomleft_y = $random_y+$border_size - $sin_theta*$mid_image_width - $cos_theta*$mid_image_height;
			my $make_point = "convert $input -fill grey -stroke black " .
					circle_string($random_x+$border_size,$random_y+$border_size,10) .
					" -fill transparent -strokeWidth 5 -draw \"polygon $topright_x,$topright_y $topleft_x,$topleft_y $bottomleft_x,$bottomleft_y $bottomright_x,$bottomright_y\"";
					#circle_string($topright_x,$topright_y,5) .
					#circle_string($topleft_x,$topleft_y,5) .
					#circle_string($bottomright_x,$bottomright_y,5) .
					#circle_string($bottomleft_x,$bottomleft_y,5);
			enact("$make_point $preview_folder/postcard_${postcard_id}_points.png");
		}
	}
	close FILE;
}

# make a visual collage of what the postcards would look like, pasted back together
sub preview_postcards {
	my ($preview_folder) = @_;

	opendir(my $dh, $preview_folder);
	my @postcards = grep /postcard.*placed\.png/, readdir $dh;
	closedir $dh;

	# first combine the first two images
	my $command_line = "composite $preview_folder/" . $postcards[1] . " $preview_folder/" . $postcards[0] . " $preview_folder/postcard_collage.png";
	enact($command_line);

	# now combine all others
	foreach my $postcard_file (@postcards[2..(scalar(@postcards)-1)]) {
		$command_line = "composite $preview_folder/$postcard_file $preview_folder/postcard_collage.png $preview_folder/postcard_collage.png";
		enact($command_line);
	}
}

# make sheets for printing postcards
sub print_postcards {
	my ($postcard_folder,$output_folder,$border_size) = @_;
	if (not($border_size)) {
		$border_size = 0;
	}
	if (not($output_folder)) {
		$output_folder = ".";
	}
	mkpath($output_folder);

	my $cards_per_page = 4;
	my $page_num = 1;

	opendir(my $dh, $postcard_folder);
	my @postcards = grep /^postcard/, readdir $dh;
	closedir $dh;

	my ($postcard_width, $postcard_height) = image_size("$postcard_folder/" . $postcards[0]);

	my $cropped_width = $postcard_width * 2 - $border_size * 2;
	my $cropped_height = $postcard_height * 2 - $border_size * 2;



	my @cur_page_images = ();
	foreach my $postcard_file (@postcards) {
		push @cur_page_images, "$postcard_folder/$postcard_file";

		if (scalar(@cur_page_images) == $cards_per_page) {
			# now put these four images together, with no border between them
			my $compose = "montage " . join(" ",@cur_page_images) . " -geometry +0+0 $output_folder/page_${page_num}_bordered.png";
			enact($compose);

			# now remove the outer border (because most printers won't print borderless)
			# with default sizes, the resulting image will be 8" x 10.5" at 150 dpi

			enact("convert $output_folder/page_${page_num}_bordered.png -crop \"${cropped_width}x$cropped_height+$border_size+$border_size\" +repage $output_folder/page_${page_num}.png");

			@cur_page_images = ();
			$page_num = $page_num + 1;
		}
	}
	# finish the last set (if the postcards are not a multiple of 4) by filling in with earlier images
	if (scalar(@cur_page_images) > 0) {
		my $postcard_number = 0;
		while (scalar(@cur_page_images) < $cards_per_page) {
			push @cur_page_images, $postcards[$postcard_number];
			$postcard_number = $postcard_number + 1;
		}
		my $compose = "montage " . join(" ",@cur_page_images) . " -geometry +0+0 $output_folder/page_${page_num}_bordered.png";
		enact($compose);
		enact("convert $output_folder/page_${page_num}_bordered.png -crop \"${cropped_width}x$cropped_height+$border_size+$border_size\" +repage $output_folder/page_${page_num}.png");
	}
}

########################################################################
# End function definition: start making the postcards
########################################################################
make_postcards($input,$postcard_width,$postcard_height,$border_size,$num_images,$output_folder,$create_previews,$center_method);
preview_postcards("${output_folder}/preview");
print_postcards("${output_folder}/postcards","${output_folder}/pages",$border_size);


