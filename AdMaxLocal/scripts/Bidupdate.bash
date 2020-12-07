
merchantUUID='76ef4bce-6544-4cb8-82b2-bc9a56787b54'

#!/bin/bash
#set -x

function usage
{
    echo;
    echo "Usage: $0 -h <mysql host>  -m <merchantUUID> -b <Bid amount> -B <BAID>"
    echo "Example: $0 -h aml1-mysql1 -m 76ef4bce-6544-4cb8-82b2-bc9a56787b54 -b 20 -B 2175"
    echo;
    exit 1
}

while [ $# -gt 0 ]
do
    case "$1" in

        # Set host mysql server
        -h)              shift; host=$1;;
        -m)              shift; merchantUUID=$1;;
        -b|--bid)        shift; Bidvalue=$1;;
        -B|--BAID)       shift; BAID=$1;;
     esac
    shift
done

if [ "$host" == "" ]; then
    usage
fi

export DATE=$(date +'%Y-%m-%d')

accountid=$(mysql -uspike -ptar63t -h $host -se "select group_concat(id) from tsacommon.searchEngineAccounts where accountID = ((select distinct accountID from tsacommon.searchEngineUsers where description like '%$merchantUUID%')) and searchEngineStatusText in ('ENABLED','PAUSED','Active');")

function BAID {

elementid=$(mysql -uspike -ptar63t -h $host -se "select group_concat(id) from tsacommon.searchEngineAccounts where accountID=(select accountID from tsacommon.searchEngineUsers where description like '%$merchantUUID%') and description like '%"$BAID"%' and searchEngineStatusText in ('ENABLED','PAUSED','Active');")

mysql -uspike -ptar63t -h $host -e "select * from \`st-tracker\`.admaxBids where elementID in ("$elementid");"

mysql -uspike -ptar63t -h $host -e "update \`st-tracker\`.admaxBids set newBid="$Bidvalue",newBidSetDate="$DATE" where elementID in ("$elementid");"

mysql -uspike -ptar63t -h $host -e "select * from \`st-tracker\`.admaxBids where elementID in ("$elementid");"

}

if [ "$BAID" == "" ]
then
mysql -uspike -ptar63t -h $host -e "select * from \`st-tracker\`.admaxBids where elementID in ($accountid);"

mysql -uspike -ptar63t -h $host -e "update \`st-tracker\`.admaxBids set newBid="$Bidvalue", newBidSetDate="$DATE" where elementID in ($accountid);"

mysql -uspike -ptar63t -h $host -e "select * from \`st-tracker\`.admaxBids where elementID in ($accountid);"
else
echo "Running the BAID function to update only baid level."
BAID
fi