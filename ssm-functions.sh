#!/bin/bash

# version 1.0

# a set of hopefully useful wrapper functions for caching and
# handling ssm parameter values

# you must source this file to be able to use the functions
# e.g.
# . path_to_this_file/ssm-functionsh.sh

# note key_id variable must be set to the id of your key
# something like key_id="d9b8a3f1-f846-3adf-8981-ebbbaaa34562"
# as this code assumes your parameters are encrypted

set -a params
set -a param_cache
set -a param_cache_names

ssm_error_file=/tmp/ssm-functions-error.$$
declare ssm_error_value
declare ssm_message_level=1


type -t md5sum 2>&1 > /dev/null
if [[ $? -eq 0 ]];then
  doMD5=doMD5Linux
  function doMD5() {
    md5sum | cut -d' ' -f1
  }
else
  alias doMD5=doMD5Mac
  function doMD5() {
    md5
  }
fi

#
# _invalid_call()
# emit an error message if an invalid function call is made
#
function _invalid_call() {
  _do_message "Invalid function call"
  ssm_error_value=-1
}

#
# _reset()
# reset the global error value to zero
#
function _reset() {
  ssm_error_value=0
}

#
# _date()
# output a date string, formated for logging
#
function _date() {
  date '+%Y-%m-%d %H:%M:%S'
}

# 
# _check_errors()
# check if an error has occured and if so output information about it
#
function _check_errors() {
  if [[ $? -ne 0 ]];then
    ssm_error_value=$?
    _do_message
  else
    ssm_error_value=0
  fi
}

#
# _getMD5 get the md5sum of the passed parameters
#
function _getMD5() {
  res=$(echo "$1" | doMD5)
  echo "var$res"
}

#
# cache_parameter()
# Function to control the local caching of ssm parameters
#
function cache_parameter() {
  local OPTIND o getmode putmode deletemode existmode
  getmode=0
  deletemode=0
  existmode=0

  while getopts ":gpde" o $@
  do
    case "${o}" in
      g) getmode=1;;
      p) putmode=1;;
      d) deletemode=1;;
      e) existmode=1;;
    esac
  done

  shift $((OPTIND -1))

  name="$1"
  value="$2"

  varname=$(_getMD5 "$name")

  if [[ $getmode -eq 1 ]];then
    echo "${param_cache[$varname]}"
    return
  fi
  if [[ $deletemode -eq 1 ]];then
    unset param_cache[$varname]
    unset param_cache_names[$varname]
    unset $varname
    return
  fi
  if [[ $existmode -eq 1 ]];then
    eval res='"${'${varname}'}"'
    if [[ $res == "" ]];then
      return 0
    else 
      return 1
    fi
  fi

  end=${#param_cache[@]}
  eval "${varname}=\"${end}\""
  param_cache[$end]="$value"
  param_cache_names[$end]="$name"
  return
}

# 
# _do_message()
# standard method of output to std error
# if there is a error file the contents of it are displayed
#
function _do_message() {
  local num
  if [[ $ssm_message_level -eq 0 ]];then
    return
  fi
  echo "${FUNCNAME[1]}" | grep -q '^_'  
  if [[ $? -eq 0  ]];then
    num=2
  else
    num=1
  fi
  if [[ $# -eq 1 ]];then
    echo "$(_date): ${FUNCNAME[${num}]}: $1" 1>&2
  else
    if [[ -r "$ssm_error_file" ]];then
      IFS=""
      grep -v "^[ \t]*$" ${ssm_error_file} | while read line
      do
        echo "$(_date): ${FUNCNAME[${num}]}: $line" 1>&2
      done
      rm ${ssm_error_file} 2>/dev/null
    fi
  fi
}

#
# get_parameter()
# get a parameter from parameter store and cache it 
# or get it from the local cache
#
function get_parameter() {
  local OPTIND o cachemode savemode name nflag
  cachemode=0
  savemode=0
  nflag=""
  while getopts ":cCn" o $@
  do
    case "${o}" in 
      c) cachemode=1;;
      C) savemode=1;;
      n) nflag="-n";;
    esac
  done

  shift $((OPTIND -1))

  if [[ $# -lt 1 ]];then
    _invalid_call
    return
  fi
  name="$1"
  _reset
  if [[ $cachemode -eq 0 ]];then
    res=$(aws ssm get-parameter --name "$name"  --with-decryption --query "Parameter.Value" --output text 2>${ssm_error_file})
    _check_errors
    if [[ $ssm_error_value -eq 0 ]];then
      if [[ $savemode -eq 1 ]];then
        cache_parameter "${name}" "${res}"
      fi
      echo $nflag "$res"
    fi
  else
    cache_parameter -e "$name"
    if [[ $? -eq 1 ]];then
      cache_parameter -g "$name"
    else
      _do_message "Parameter($name) is not cached"
      ssm_error_value=-2
    fi
  fi
}

#
# ssm_list_cache()
# List the contents of the local cache
#
function ssm_list_cache() {
  for p in "${param_cache_names[@]}"
  do
    echo "Parameter $p"
    echo "Value:"
    echo "$(cache_parameter -g "$p")"
  done
}

#
# populate_params_array()
# populate the params array with all the parameter names from parameters store
#
function populate_params_array() {
  params=($(list_parameters))
}

# 
# list_parameters()
# get all the parameters names from the parameter store
#
function list_parameters() {
  _reset
  aws ssm describe-parameters --query "Parameters[*].Name" --output text
  _check_errors
}

delete_large_parameter() {
  local OPTIND o verbose base name second parameter vflag

  verbose=0
  vflag=""

  while getopts ":v" o $@
  do
    case "${o}" in 
      v) verbose=1;vflag="-v";;
    esac
  done

  shift $((OPTIND -1))

  if [[ $# -lt 1 ]];then
    _invalid_call
    return
  fi
  name="$1"

  [[ $verbose -eq 1 ]] && _do_message "Deleting $name in parts"
  _reset
  base="$(basename "$name")"

  # it would be stupid to go up to i

  for second in a b c d e f g h i
  do
    parameter="$name/${base}_a${second}"
    check_parameter "$parameter"
    if [[ $? -gt 0 ]];then
      delete_parameter $vflag "$parameter"
    else
      break
    fi
  done
}

#
# delete_parameter()
# delete the passed parameter name from the aws store
# use with care
#
function delete_parameter() {
  local OPTIND o verbose name 

  verbose=0

  while getopts ":v" o $@
  do
    case "${o}" in 
      v) verbose=1;;
    esac
  done

  shift $((OPTIND -1))

  if [[ $# -lt 1 ]];then
    _invalid_call
    return
  fi
  name="$1"
  _reset
  check_parameter "$name"
  if [[ $? -eq 0 ]];then
    [[ $verbose -eq 1 ]] && _do_message "Parameter \"$name\" does not exist - ignoring"
    return
  fi
  [[ $verbose -eq 1 ]] && _do_message "Removing parameter $name"
  aws ssm delete-parameter --name "$name"
  _check_errors
}

function get_large_parameter() {
  local OPTIND o verbose vflag base name part once

  verbose=0
  check=1
  vflag=""
  cflag=""
  while getopts ":cv" o $@
  do
    case "${o}" in 
      v) verbose=1;vflag="-v";;
      c) check=1;cflag="-c";;
    esac
  done
  shift $((OPTIND -1))

  if [[ $# -ne 1 ]];then
    _invalid_call
    return
  fi

  name="$1"
  base="$(basename "$name")"
  once=0
  for second in a b c d e f g h i
  do
    parameter="$name/${base}_a${second}"
    check_parameter "$parameter"
    if [[ $? -gt 0 ]];then
      once=1
      get_parameter -n "$parameter"
    else
      break
    fi
  done
  [[ $once -eq 1 ]] && echo
}

function put_large_parameter() {
  
  local OPTIND o verbose check vflag cflag base filename name basepart

  verbose=0
  check=1
  vflag=""
  cflag=""
  while getopts ":cv" o $@
  do
    case "${o}" in 
      v) verbose=1;vflag="-v";;
      c) check=1;cflag="-c";;
    esac
  done
  shift $((OPTIND -1))

  filename="$1"
  name="$2"
  base=$(basename "$name")
  [[ $verbose -eq 1 ]] && _do_message "Adding $name in parts"
  rm -rf /tmp/ssm-functions.$$
  mkdir -p /tmp/ssm-functions.$$
  split -b 4096 "$filename" /tmp/ssm-functions.$$/${base}_
  for part in /tmp/ssm-functions.$$/${base}_*
  do
    basepart=$(basename $part)
    put_parameter $vflag $cflag -f "$part" "$name/$basepart"
  done
  rm -rf /tmp/ssm-functions.$$
}

#
# put_parameter()
# put the passed parameter into the aws store.
# Note files can be used with -f
# -c checks the parameter exists and only puts if it does not
#
function put_parameter() {

  local OPTIND o filemode checkmode verbosemode filename name value
  filemode=0
  checkmode=0
  verbosemode=0

  while getopts ":f:cv" o $@
  do
    case "${o}" in 
      f) filemode=1;filename=${OPTARG};;
      c) checkmode=1;;
      v) verbosemode=1;;
    esac
  done

  shift $((OPTIND -1))
  name="$1"

  if [[ $checkmode -eq 1 ]];then
    check_parameter "$name"
    if [[ $? -eq 1 ]];then
      [[ $verbosemode -eq 1 ]] && _do_message "Parameter \"$name\" already exists - not overwriting"
      return
    fi
  fi

  [[ $verbosemode -eq 1 ]] && _do_message "Adding parameter $name"

  if [[ $filemode -eq 1 ]];then
    if [[ $# -lt 1 ]];then
      _invalid_call
      return
    fi
    if [ ! -r "$filename" ];then
      _do_message "Cannot read from file ($filename)"
      return
    fi
    value="$(cat $filename)"
  else
    if [[ $# -lt 2 ]];then
      _invalid_call
      return
    fi
    value="$2"
  fi
  _reset
  aws ssm put-parameter --name "$name" --value "${value}" --type "SecureString" --key-id "${key_id}" --overwrite 2>&1 > /dev/null
  _check_errors
}

#
# output_parameters()
# List all of the parameters in the aws parameter store
#
function output_parameters() {
  local p
  for p in $(list_parameters)
  do
    echo $p
  done
}

#
# eval_ssm()
# get a paraemeter and eval it as a command
#
function eval_ssm() {
  if [[ $# -lt 1 ]];then
    _invalid_call
    return
  fi
  res="$(get_parameter $1)"
  eval "$res"
}
#
# check_parameter()
# check that the passed parameter exists, 1 yes, 0 no
#
function check_parameter() {
  local name res
  if [[ $# -lt 1 ]];then
    _invalid_call
    return
  fi
  name="$1"
  _reset
  res=$(aws ssm describe-parameters --parameter-filters "Key=Name,Option=Equals,Values=$name" --output=text | wc -l)
  _check_errors
  return $res
}

