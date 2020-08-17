#!/bin/bash

# a set of hopefully useful wrapper functions for caching and
# handling ssm parameter values

# you must source this file to be able to use the functions
# . path_to_this_file/ssm-functionsh.sh

# note key_id variable must be set to the id of your key
# something like key_id="d9b8a3f1-f846-3adf-8981-ebbbaaa34562"
# as this code currently assumes your parameters are encrypted

set -a params
set -a param_cache
set -a param_cache_names

ssm_error_file=/tmp/ssm-functions-error.$$
declare ssm_error_value
declare ssm_message_level=1

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
  res=$(echo "$1" | md5)
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
  local OPTIND o cachemode savemode
  cachemode=0
  savemode=0
  while getopts ":cC" o $@
  do
    case "${o}" in 
      c) cachemode=1;;
      C) savemode=1;;
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
      echo "$res"
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

#
# delete_parameter()
# delete the passed parameter name from the aws store
# use with care
#
function delete_parameter() {
  if [[ $# -lt 1 ]];then
    _invalid_call
    return
  fi
  name="$1"
  _reset
  aws ssm delete-parameter --name "$name"
  _check_errors
}

#
# put_parameter()
# put the passed parameter into the aws store.
# Note files can be used with -f
#
function put_parameter() {

  local OPTIND o filemode
  filemode=0

  while getopts ":f:" o $@
  do
    case "${o}" in 
      f) filemode=1;filename=${OPTARG};;
    esac
  done

  shift $((OPTIND -1))

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
    name="$1"
  else
    if [[ $# -lt 2 ]];then
      _invalid_call
      return
    fi
    name="$1"
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

