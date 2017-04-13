#targetcli to Rapido VM parser

#path variables
core=/sys/kernel/config/target/core

#check for root
if (( $EUID != 0 )); then
  echo "This script must be run as root."
  exit
fi

#how many storage objects do we have?
stor_count=$(cat /etc/target/saveconfig.json | jq '.storage_objects | length')
#iterate over all storage objects
for (( i=0; i<=($stor_count-1); i++)); do
  #check if plugin is fileio
  check_plugin=$(jq -c ".storage_objects[$i] | {plugin}" /etc/target/saveconfig.json)
  if [ $check_plugin = '{"plugin":"fileio"}' ]; then
    #check if fileio directory exists
    if [ -d $core/fileio_$i ]; then
      echo "fileio directory exists, continue..."
    else
      echo "fileio directory does not exist, creating new one..."
      mkdir -p $core/fileio_$i
    fi
    #get storage_object name
    str_name=$(jq -c -r ".storage_objects[$i] | .name" /etc/target/saveconfig.json)
    echo $str_name
    #check for storage object directory
    if [ -d $core/fileio_$i/$str_name ]; then
      echo "storage object directory exists, continue..."
    else
      echo "storage object directory does not exist, creating new one..."
      mkdir -p $core/fileio_$i/$str_name/
    fi
    #get all attributes and iterate over them with jq
    for attr in $(ls $core/fileio_$i/$str_name/attrib); do
      jq_attr=$(jq -c ".storage_objects[$i] | .attributes | .$attr" /etc/target/saveconfig.json)
      echo $jq_attr > $core/fileio_$i/$str_name/attrib/$attr
    done
  fi
  if [ $check_plugin = '{"plugin":"block"}' ]; then
    #check if iblock directory exists
    if [ -d $core/iblock_$i ]; then
      echo "iblock directory exists, continue..."
    else
      echo "iblock directory does not exist, creating new one..."
    fi

    #get device name
    str_name=$(jq -c -r ".storage_objects[$i] | .name" /etc/target/saveconfig.json)
    #echo $str_name

    #check if storage object directory exists
    if [ -d $core/iblock_$i/$str_name ]; then
      echo "storage object directory exists, continue..."
    else
      echo "storage object directory does no exist, creating new one..."
      mkdir -p $core/iblock_$i/$str_name
    fi

    #set device path to /dev/vda
    echo "/dev/vda" > $core/iblock_$i/$str_name/udev_path

    #count the attributes
    attr_count=$(jq -c ".storage_objects[$i] | .attributes | length" /etc/targetsaveconfig.json)
    echo "$attr_count attributes found, applying..."

    #apply attributes
    for attr in $(ls $core/fileio_$i/$str_name/attrib); do
      jq_attr=$(jq -c ".storage_objects[$i] | .attributes | .$attr" /etc/target/saveconfig.json)
      echo $jq_attr | tee -a $core/fileio_$i/$str_name/attrib/$attr
    done
  fi
done
