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

# Lets color a bit. This is clearly a waste of time... (setup in load function).
OUTPUTCOLOR=
NOCOLOR=
SCRIPTNAME="yr-to-qr-thumb"
function die() {
    echo "${OUTPUTCOLOR}[${SCRIPTNAME}]${NOCOLOR} $(date +%T) ERROR:" "$@"
    # echo "$(date +%T.%N) ERROR:" "$@" >> ${LOG_FILE}
    exit 1
}

function info() {
    echo "${OUTPUTCOLOR}[${SCRIPTNAME}]${NOCOLOR} $(date +%T) INFO:" "$@"
    # echo "$(date +%T.%N) INFO:" "$@" >> ${LOG_FILE}
}

function warn() {
    echo "${OUTPUTCOLOR}[${SCRIPTNAME}]${NOCOLOR} $(date +%T) WARN:" "$@"
}

function debug() {
    echo "${OUTPUTCOLOR}[${SCRIPTNAME}]${NOCOLOR} $(date +%T) DEBUG:" "$@"
}

# Setup some stuff.

# Set some variables on load - most "important": If tty output, lets put some colors on.
function onLoad() {
  if [ -t 1 ] ; then
    OUTPUTCOLOR=$(tput setaf 2)  # Green
    NOCOLOR=$(tput sgr0)
  fi
}
onLoad





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
which dirname &> /dev/null || die "Unable to find the program dirname"
which curl &> /dev/null || die "Unable to find the program curl"
which qrencode &> /dev/null || die "Unable to find the program qrencode"
which jq &> /dev/null || die "Unable to find the program jq"

BASEDIR=$(dirname $0) || die "Unable to call dirname for $0. Please install dirname"

# The frame used for overlay
# FRAME="${BASEDIR}/templates/film-frame-alpha.png"
FRAME="${BASEDIR}/templates/film-frame-high.png"
#BACKGROUND="${BASEDIR}/templates/background.png"
BACKGROUND="${BASEDIR}/templates/background-high.png"
FRAME_INNER_DIMENSIONS="1356x744"
FRAME_X_OFFSET=351
QR_SIZE=17
QR_Y_OFFSET=175



# Approach
# 1: Get the list of videos in json format, store to tmp file
ALLINFO=$(mktemp)
info "Getting content of playlist"
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

debug "Output from YT:"
cat ${ALLINFO}

info "Parsing response in $ALLINFO"
# 2: "Parse" all the videos for title and videoId
LENGTH=$(jq '.items | length' $ALLINFO) || die "Unable to get length of items in response"
info "Number of items in response: $LENGTH"
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
    THUMBNAIL=$(jq '.items['$i'].snippet.thumbnails.maxres.url' $ALLINFO) || die "Unable to get thumbnail for item $i in response. See $ALLINFO"
    
    # Check we have the right kind, and a title is present
    test -n "$TITLE" || die "Title not set for item $i"
    test "$KIND" = "\"youtube#video\"" || die "Item $i does not have kind youtube#video, but $KIND"

    # Status information
    info "Item $i has id $VIDEOID and title $TITLE"

    # Clean up names for ", to make easier to use filenames
    TITLE=$(echo $TITLE | sed 's/[\(\)\&\!\:\"\$\?\#\/]//g;s/\s/_/g' | sed "s/'//g")
    # These needs " front and back removed
    VIDEOID=$(echo $VIDEOID | sed 's/^\"//;s/\"$//')
    THUMBNAIL=$(echo ${THUMBNAIL} | sed 's/^\"//;s/\"$//')

    debug "Videoid sanitized to ${VIDEOID}"
    debug "Title sanitized to ${TITLE}"
    
    # 3: Use curl to retrieve the thumbnail in high resolution
    info "Getting thumbnail in high res from ${THUMBNAIL}"
    THUMB=$(mktemp --suffix=.jpg)
    debug "Storing thumb in ${THUMB}"
    curl -s -o "$THUMB" "${THUMBNAIL}" || die "Unable to get thumb for item $i, videoId=$VIDEOID"
    debug "Dimensions of thumb:" $(identify -format '%wx%h' "${THUMB}")

    # TESTING: Resize thumb to frame inner dimensions
    info "Resizing thumb"
    THUMB2=$(mktemp --suffix=.jpg)
    convert "${THUMB}" -resize "${FRAME_INNER_DIMENSIONS}" "${THUMB2}"
    THUMB=${THUMB2}
    debug "Dimensions of thumb after resize:" $(identify -format '%wx%h' "${THUMB}")
    
    
    # 4: Use qrencode to create the qrcode
    QR=$(mktemp --suffix=.png)
    qrencode -o "$QR" -t png --size=${QR_SIZE} 'https://www.youtube.com/watch?v='$VIDEOID || die "Error calling qrencode for item $i, videoId=$VIDEOID"
    debug "Dimensions of qr:" $(identify -format '%wx%h' "${QR}")
    # 5: (Scale the image) and overlay qrencode on it, together with a frame...
    TMPIMG1=$(mktemp --suffix=.png)
    # First the film frame and thumb.
    info "Compositing thumb onto film frame"
    debug "Dimensions of frame:" $(identify -format '%wx%h' "${FRAME}")
    composite -gravity center "$THUMB" "${FRAME}" "$TMPIMG1" || die "Unable to composite film frame on thumb for item $i, videoId=$VIDEOID"
    debug "Dimensions of ${TMPIMG1}:" $(identify -format '%wx%h' "${TMPIMG1}")

    # Then, put it on the background
    info "Adding background"
    debug "Dimensions of background:" $(identify -format '%wx%h' "${BACKGROUND}") 
    TMPIMG2=$(mktemp --suffix=.png)
    convert "$BACKGROUND" "$TMPIMG1" -geometry +${FRAME_X_OFFSET}+0 -composite "$TMPIMG2" || die "Unable to convert file ${TMPIMG1}"
    debug "Dimensions of tmpimg2:" $(identify -format '%wx%h' "${TMPIMG2}")
    # And, put the qr on top, then into the final picture
    # 6: Save the final image, using the title of the video as the name
    info "Putting QR code on top"
    OUTPUT="$i-$TITLE.png"
    convert "$TMPIMG2" "$QR" -geometry +0+${QR_Y_OFFSET} -composite "$OUTPUT" || die "Unable to convert file ${TMPIMG2} to ${OUTPUT}"
    info "Final image in $OUTPUT"
    debug "Dimensions of final image:" $(identify -format '%wx%h' "${OUTPUT}")

    exit 1
    
done

