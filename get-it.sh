#! /bin/bash

# Script to create a number of images with qr codes from a youtube playlist




######################################################################
# Function to die for...
function die() {
    local frame=0
    while caller $frame; do
        ((frame++));
    done
    echo "Error:" "$@"
    exit 1
}

######################################################################
function usage() {
    echo "Usage: $0 <playlistid> <apikey>"
    echo
    echo "Example: $0 PL9728A6605538F807 your-key-here"
    exit;
}

PLAYLISTID="$1"
APIKEY="$2"

test "x$APIKEY" != "x" || usage

# We need the program curl and qrencode and jq
which curl &> /dev/null || die "Unable to find the program curl"
which qrencode &> /dev/null || die "Unable to find the program qrencode"
which jq &> /dev/null || die "Unable to find the program jq"

# Approach
# 1: Get the list of videos in json format, store to tmp file
ALLINFO=$(mktemp)
echo "Getting content of playlist"
# Note the 50 limitation. - more than that requires pagination.
curl -s -o "$ALLINFO" 'https://www.googleapis.com/youtube/v3/playlistItems?maxResults=50&part=snippet%2C+id&playlistId='$PLAYLISTID'&key='$APIKEY || die "Unable to get playlist info from youtube, using PLAYLISTID=$PLAYLISTID and APIKEY=$APIKEY"

# Here is how an error response looks:
# {
#  "error": {
#   "errors": [
#    {
#     "domain": "usageLimits",
#     "reason": "keyInvalid",
#     "message": "Bad Request"
#    }
#   ],
#   "code": 400,
#   "message": "Bad Request"
#  }
# }
# Not checking for it though.


echo "Parsing response in $ALLINFO"
# 2: "Parse" all the videos for title and videoId
LENGTH=$(jq '.items | length' $ALLINFO) || die "Unable to get length of items in response"
echo "Number of items in response: $LENGTH"
test "$LENGTH" -eq 0 && {
    cat $ALLINFO
    die "Unable to parse $ALLINFO (see above) or no elements in playlist"
}

# Iterate all elements
for (( i=0; i<"$LENGTH"; i++ ))
do
    # Note, strings returned from jq is enclosed in "" pairs... - we strip it below
    TITLE=$(jq '.items['$i'].snippet.title' $ALLINFO) || die "Unable to get title for item $i in response. See $ALLINFO"
    KIND=$(jq '.items['$i'].snippet.resourceId.kind' $ALLINFO) || die "Unable to get kind for item $i in response. See $ALLINFO"
    VIDEOID=$(jq '.items['$i'].snippet.resourceId.videoId' $ALLINFO) || die "Unable to get videoId for item $i in response. See $ALLINFO"

    # Check we have the right kind, and a title is present
    test -n "$TITLE" || die "Title not set for item $i"
    test "$KIND" = "\"youtube#video\"" || die "Item $i does not have kind youtube#video, but $KIND"

    # Status information
    echo "Item $i has id $VIDEOID and title $TITLE"
    TITLE=$(echo $TITLE | sed 's/^\"//;s/\"$//')
    VIDEOID=$(echo $VIDEOID | sed 's/^\"//;s/\"$//')
    
    # 3: Use curl to retrieve the thumbnail in high resolution
    echo "Getting thumbnail in high res"
    THUMB=$(mktemp --suffix=.jpg)
    # Maxresdefault does not seem to work for all, so use hqdefault
    curl -s -o "$THUMB" 'http://img.youtube.com/vi/'$VIDEOID'/hqdefault.jpg' || die "Unable to get thumb for item $i, videoId=$VIDEOID"

    # 4: Use qrencode to create the qrcode
    # 5: Scale the image and overlay qrencode on it
    # 6: Save the final image, using the title of the video as the name


    
done

# Note: Very little error checking is done...

#
# 1: Get the list of videos in json format, store to tmp file
# 2: "Parse" all the videos for title and videoId
# For each
# 3: Use curl to retrieve the thumbnail in high resolution
# 4: Use qrencode to create the qrcode
# 5: Scale the image and overlay qrencode on it
# 6: Save the final image, using the title of the video as the name