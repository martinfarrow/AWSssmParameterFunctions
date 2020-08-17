#!/bin/bash

# note key_id variable must be set to the id of your key
# something like key_id="d9b8a3f1-f846-3adf-8981-ebbbaaa34562"
# as this code assumes your parameters are encrypted

key_id="your key here"

. ./ssm-functions.sh

# go through these and change zero, to 1 to get each section to
# run, if you want to try stuff out, remember this WILL add
# and delete parameters into your parameter store if you have
# enough privilege

# example deleting a parameters
if [ 0 -eq 1 ];then
  delete_parameter "/my/test"
  exit
fi

# general operations
if [ 0 -eq 1 ];then
  echo "---put"
  put_parameter "/my/test"  "balh"
  #
  echo "---get and cache"
  get_parameter -C "/my/test"

  # deliberate error
  echo "------get from cache"
  cache_parameter -e "/my/testy"
  echo $?

  get_parameter -c "/my/test"
  echo "--list cache"
  ssm_list_cache
  #
  exit
fi

# example with a file, you need to create 2-build.sh
if [ 0 -eq 1 ];then
  output_parameters
  echo "---"
  put_parameter_from_file "/my/test" "2-build.sh"
  echo "---"
  output_parameters
  echo "-----getting"
  x=$(get_parameter "/my/test")
  echo "$x"
  exit
fi

# more dangerous putting and evaling you need to write 2-build.sh
if [ 0 -eq 1 ];then
  echo "---putting /my/test"
  put_parameter -f "2-build.sh" "/my/test"

  echo "----listing"
  output_parameters

  echo "-----getting"
  x=$(get_parameter "/my/test")
  echo "$x"

  echo "-----evaling"
  eval_ssm "/my/test"
fi

# examples of pulldown ALL parameters, this might not be
# sensible if you have loads

if [ 0 -eq 1 ];then
  echo "-----populating"
  populate_params_array

  echo "-------deleting"
  delete_parameter "/my/test"

  echo "-------"
  output_parameters

  echo "----list params array"
  for p in "${params[@]}"
  do
    echo $p
  done
fi
