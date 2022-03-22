#!/bin/bash
dc_home=~/src/work/dc
dc_filename_prefix=docker-compose.
dc_filename_suffix=.yml
dc_dataset=$DOCK_DATASET
default_style="all"
test -z $dc_dataset && dc_dataset=demo-dev-pmapwebcore
myxtmpfile=/tmp/start-myx$$
debug=false
nl='
'

trap "test -f $myxtmpfile && rm $myxtmpfile" 0

Usage="$0 [--help] [--debug] [--dataset index-json-tag] [--only container-list] [--style style-string]

    A 'docker-compose pull' command will be executed if it is more than 24 hrs since the
    last pull.

    Options:
      --help       display this message
      --debug      display, but do not execute, docker-compose commands
      --dataset <index.json-tag>
                name of dataset tag in index.json to use overrides the DOCK_DATASET
                envar and defaults to 'demo-dev-pmapwebcore' if none set.
      --only <container-name(s)>
                restart the given container list, typically just 'myx' or 'ateb-db'.
      --style <style-string>
                is an optional string used to specify a different docker-compose file.
                It will be used to generate a file name of the form:
                        ${dc_filename_prefix}'style-string'${dc_filename_suffix}

                Default style is ${default_style}
"
#
# This restarts all of my "favorite" local containers.  There may be more efficient ways to do this
# but this way works consistently

# These are "all" the containers I use; adjust this list if other containers are/aren't needed.
all_containers="ateb-db dataloader identity-rest ateb-amq myx hr-services-rest hr-gateway ope-gateway ope-app hr-app obcgui"
containers=$all_containers

#
# Show some DOCK_variables that occasionally change so we can be subtly reminded of differences
echo "
Representative DOCK_ variable values:
  $(printenv | egrep 'DATASETS|COMPONENT|DATASET|MVNREPO|HR_DIST' | sed '2,$s/^/  /')
-----"

style=$default_style
while true
do
  case $1 in
    --debug|--deb*|-d)
      debug=true
      ;;

    --help|--he*|-h)
      echo 1>&2 "? ${Usage}"
      filespec=${dc_home}/${dc_filename_prefix}
      echo 1>&2 "-----${nl}    Known styles are:" $(echo ${filespec}* | sed "s=${filespec}==g;s=.yml==g")
      exit 2
      ;;

    --only|--o*|-o)
      shift
      containers=$@
      break
      ;;

    --dataset|--data*)
      shift
      dc_dataset=$1
      ;;

    --style|--st*|-s)
      shift
      style=$1
      ;;

    -*)
      echo 1>&2 "?Unknown option: $1"
      exit 3
      ;;

    "")
      break
      ;;

    *)
      echo 1>&2 "?extraneous arguments found on line: '$*'"
      exit 4
      ;;
  esac
  shift
done

dc_filename=${dc_filename_prefix}$style${dc_filename_suffix}

dc_full_name=${dc_home}/${dc_filename}
test -r ${dc_full_name} ||
  {
    echo 1>&2 "? docker-compose file not found: ${dc_full_name}${nl}-----${nl}${Usage}"
    exit 1
  }

docker_compose_cmd="docker-compose -f $dc_filename"

case $debug in
  true) say 'Debugging' ;;
esac

case $style in
  all) ;;
  *)
    say "style ${style:-"default"}"  # if style is not set, say "default"
    ;;
esac

#++ define functions
#
function debug_log {
  echo "  Debugging, so not executing: '$@'"
}

function docker_pull_if_needed {
  timestamp_file="/tmp/last_docker_pull.timestamp"
  a_day=$((24*60*60))
  now=$(date +'%s')

  if test -e $timestamp_file
  then
    last_pull=$(stat -f '%m' $timestamp_file)
    age=$(($now - $last_pull))

    # always pull if a --style was provided
    if test -z "$style" && test $age -le $a_day
    then
      echo "-- pull not needed"
      return
    fi
  fi

  case $debug in
    true)
      debug_log "pushd $dc_home && $docker_compose_cmd pull $containers"
      ;;

    *)
      pushd $dc_home && $docker_compose_cmd pull $containers || {
        echo 1>&2 "?docker-compose pull failed"
        exit 2
      }
      popd
      touch $timestamp_file
      ;;
  esac
}

function block_until_dataloader_is_done {
  last_msg="Sleeping forever to keep this container alive..."
  seconds=0
  pause=15
  container=dataloader

  echo "${nl}Waiting for ${container} startup to finish. . ."
  while true
  do
    test "$(docker logs --tail 1 ${container} 2>&1)" = "$last_msg" && break
    docker ps --all | grep --ignore-case --silent "exited.*${container}" && {
      echo "${nl}${container} container abnormally exited!"
      say "${container} abnormal exit"
      return 5
    }
    seconds=$((seconds + $pause))
    sleep $pause
    echo -ne "$(($seconds / 60)) min, $(($seconds % 60)) seconds  \r"
  done

  echo "${nl}${container} has run to completion"
}

function block_until_service_ping_succeeds {
  name=$1
  name_say=$2
  ping_cmd=$3
  max_checks=$4

  pingtmpfile=/tmp/ping$$

  case $max_checks in
    "")
      max_checks=20
      ;;
  esac

  last_msg="Sleeping forever to keep this container alive..."
  elapsed=0
  pause=15

  say "${name_say} check" # mispelled for correct pronunciation
  echo "${name} container booted. Waiting for ready signal. . ."

  # Once started, it takes time for service to be ready for business.
  # So, this code waits for the "open" sign to appear
  ping_count=0
  while true
  do
    $ping_cmd > $pingtmpfile 2>&1
    ping_check_status=$?
    case $ping_check_status in
      0)   # success...we are up and running
        break ;;
      52)  # empty reply from server...try again
          count=$(($count + 1))
          test $count -ge $max_checks && {
          echo 1>&2 "${nl}?${name} does not seem to have come up properly"
          say "${name_say} did not start"
          exit 2
          }
          ;;
      *)
        echo 1>&2 "? Unexpected return from curl/ping: '$ping_check_status'"
        cat 1>&2 "${nl}$pingtmpfile"
        break ;;
    esac

    elapsed=$((elapsed + $pause))
    sleep $pause
    echo -ne "$(($elapsed / 60)) min, $(($elapsed % 60)) seconds  \r"
  done
  test -e $pingtmpfile && rm $pingtmpfile
  echo ""
}

# Note: it currently takes about 10 minutes for myx to become ready in a new container
function block_until_myx_is_up {
  ping_cmd="curl -S localhost:18181/cxf/api/pmap/ping"
  block_until_service_ping_succeeds Myx Mix "$ping_cmd" 40
}

function block_until_hr_services_is_ready {
  ping_cmd="curl -S http://localhost:18001/cxf/api/healthreview/v1/ping"
  block_until_service_ping_succeeds hr-services "H R services" "$ping_cmd"
}

function start_containers_in_list {
  list=$@

  for container in $list
  do
    case $debug in
      true)
        debug_log "$docker_compose_cmd up -d $container"
        ;;

      *)
        ( cd $dc_home
          export DOCK_DATASET=$dc_dataset
          $docker_compose_cmd up -d $container
        )
        ;;
    esac
  done
}

function verify_these_containers_are_running {
  containers=$@

  error=0
  missing_containers=""
  sleep 1 # Pause to allow failing containers to fail; is there a better way to do this w/o false success/failures?
  for container in $containers
  do
    echo
    docker ps -all | grep --ignore-case --silent "exited.*${container}" && {
      echo 2>&1 "$container is not running"
          error=$((error + 1))
          missing_containers="$missing_containers $container"
        }
  done

  case $error in
    0)
      echo 1>&2 "Restart completed for '$containers'."
      case $containers in
        $all_containers)
          say 'Restart completed for all containers'
          ;;
        *)
          say "Restart completed for $containers"
          ;;
      esac
      ;;

    *)
      echo 1>&2 "? Container $missing_containers not started"
      say "Restart failure. ${error} containers not started"
      exit $error
      ;;
  esac
}
#
#-- End define functions

echo "${nl}Restarting [${containers}] using $dc_home/$dc_filename"

docker_pull_if_needed

echo `date +'%D %I:%M%p'`: Operating on these containers: $containers
test -z "$containers" || {
  echo "docker rm -r $containers"
  case $debug in
    true)
      debug_log "docker rm -f $containers"
      ;;

    *)
      docker rm -f $containers
      ;;
  esac
}

start_containers_in_list $containers

case $containers in
  *dataloader*)
    block_until_dataloader_is_done
    ;;

  ## TODO: is this still needed?
  myx)
    ;;

  "obcgui myx ateb-amq identity-rest")
    echo 1>&2 "== restarting with 'quick' db"
    ;;

  *)
    verify_these_containers_are_running $containers
    ;;
esac

block_until_myx_is_up
block_until_hr_services_is_ready

case $style in
  quick)
    echo "Workaround for Quick style: refresh materialized views. . ."
    psql -U ateb -d ateb -h localhost -c 'refresh materialized view medispan.ndc;' &&
      psql -U ateb -d ateb -h localhost -c 'refresh materialized view medispan.drug_name;'
    ;;
esac

echo "Data ready"
say "Data ready"
date
exit 0
