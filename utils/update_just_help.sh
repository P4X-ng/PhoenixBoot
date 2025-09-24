#!/bin/bash

#export JUST_TARGETS=$(cat Justfile | grep -oE '^[a-z\-]*:' | grep -v help | tr -d '\:');
mapfile -t lines < Justfile
for i in "${lines[@]}"
do
    echo $i    
    i=$(echo -n $i | tr -d '\n')
  if [[ $i =~ help\: ]]; then
     echo "$i"
  elif [[ -z $i ]] || [[ -n $(echo -n $i | grep -E '\:')  ]]; then
     echo "i none or has : see $i"
      exit 0
  else
    echo -e "i is $i"
    continue
  fi
done
