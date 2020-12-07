#!/bin/bash
EMAIL_ID=Kirtiranjan.sahoo@admaxlocal.com
SUBJECT=CMG Taxonomy Report
default_dir="cmg_taxonomy_report"
function usage {

    echo;
    echo "Usage: $0 -h <some_host> -u <db_user> -p <db_password>  [ -o <output_directory> ]"
    echo;
    echo "Example: $0 -h aml22-mysql1 -u spike -p tar63t  -o /home/user.user/Desktop/  "
    echo;
    echo "defaults: output_dir=/tmp/${default_dir}/"; echo;

        exit 1
}

while [ $# -gt 0 ]
do
    case "$1" in
        -h|--db-host)       shift;  HOST=$1;;
        -u|--db-username)   shift;  SQL_USER=$1;;
        -p|--db-password)   shift;  PASS=$1;;
        -o|--out-dir)       shift;  OUT_DIR=$1;;   
    esac
    shift
done

if [ "$HOST" == "" ]; then
    usage
fi

SQL_QUERY_AREA="SELECT 'id','businessArea' UNION ALL SELECT id,description FROM mms_common.businessAreas WHERE status='Active';"
SQL_QUERY_LOCATION="SELECT 'id','businessLocation' UNION ALL SELECT id,description FROM mms_common.businessLocations WHERE status='Active';"

if [ ! -z "${OUT_DIR}" ]; then
    echo "$OUT_DIR" | grep '/$'

    if [ $? -ne 0 ]; then
        echo "You need to put a trailing slash at the end of your output location."
        echo "Exiting..."
        exit
    fi

    if [ ! -d ${OUT_DIR} ]; then
        echo "Creating \"${OUT_DIR}\" directory."
        mkdir "${OUT_DIR}"
        echo "Using ${OUT_DIR} directory."
    else
        echo "Using ${OUT_DIR} directory."
    fi
else
    echo ${OUTPUT_DIR:="/tmp/${default_dir}/"} >> /dev/null
    if [ ! -d $OUTPUT_DIR ]
    then
        mkdir $OUTPUT_DIR
    fi
fi

echo ${OUTPUT_DIR:=$OUT_DIR} >> /dev/null

echo "Using $OUTPUT_DIR for output directory."

AREA=$(mysql -h$HOST -u$SQL_USER -p$PASS -B -e "$SQL_QUERY_AREA" > $OUTPUT_DIR/businessArea-mapping-key.csv)
LOCATION=$(mysql -h$HOST -u$SQL_USER -p$PASS -B -e "$SQL_QUERY_LOCATION" > $OUTPUT_DIR/businessLocation-mapping-key.csv)

for file in $AREA $LOCATION
do
sed -e 's/\\/*/g; s/\t/,"/g;s/*,/*/g; s/*/,/g; s/$/"/g;' -e  '1d' $file > "$OUTPUT_DIR/$file"
done
mail -s $SUBJECT $EMAIL_ID $