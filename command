#!/bin/bash
set -e
set -u

ABP_ENV=local
PARAMETER=

BASE_DIR=$(dirname $0)
SCRIPT_PATH="$( cd "${BASE_DIR}" && pwd -P )"

load_env(){
  ENV_FILE="${SCRIPT_PATH}/env/${ABP_ENV}.env"
  if test -f "${ENV_FILE}"; then
      source "${ENV_FILE}"
  fi
}
load_env

exit_err() {
  echo "ERROR: ${1}" >&2
  exit 1
}

# Usage: -h, --help
# Description: Show help text
option_help() {
  printf "Usage: %s [options...] COMMAND <parameter> \n\n" "${0}"
  printf "Default command: --help\n\n"

  echo "Options:"
  grep -e '^[[:space:]]*# Usage:' -e '^[[:space:]]*# Description:' -e '^option_.*()[[:space:]]*{' "${0}" | while read -r usage; read -r description; read -r option; do
    if [[ ! "${usage}" =~ Usage ]] || [[ ! "${description}" =~ Description ]] || [[ ! "${option}" =~ ^option_ ]]; then
      exit_err "Error generating help text."
    fi
    printf " %-32s %s\n" "${usage##"# Usage: "}" "${description##"# Description: "}"
  done

  printf "\n"
  echo "Commands:"
  grep -e '^[[:space:]]*# Command Usage:' -e '^[[:space:]]*# Command Description:' -e '^command_.*()[[:space:]]*{' "${0}" | while read -r usage; read -r description; read -r command; do
    if [[ ! "${usage}" =~ Usage ]] || [[ ! "${description}" =~ Description ]] || [[ ! "${command}" =~ ^command_ ]]; then
      exit_err "Error generating help text."
    fi
    printf " %-32s %s\n" "${usage##"# Command Usage: "}" "${description##"# Command Description: "}"
  done
}

# Usage: -p, --prod
# Description: Set the ABP env to production (default local)
option_prod() {
  ABP_ENV=prod
  load_env
}

# Command Usage: run
# Command Description: Gradle project bootRun
command_run() {
  hugo server --minify --theme book
}

# Command Usage: test <unit|function|integration>
# Command Description: Gradle project run unit|function|integration test
command_test() {
  ./gradlew :cleanTest :test --tests "com.abp.${PARAMETER}.*"
}

# Command Usage: clean
# Command Description: Gradle project clean
command_clean() {
  gradle_clean
}

# Command Usage: up
# Command Description: Docker compose start up brand new database container 
command_up() {
  docker-compose -f ./docker/docker-compose.yml up -d
  check_msg "Docker container up" 
  echo "Database provision..."
  ./docker/provision/up.sh
}

# Command Usage: down
# Command Description: Docker compose remove database instance totally 
command_down() {
  docker-compose -f ./docker/docker-compose.yml down
}

# Command Usage: console
# Command Description: Docker enter database console for sql server sqlcmd
command_console() {
  docker exec -it mssql /opt/mssql-tools/bin/sqlcmd -S localhost -U "${DB_USERNAME}" -P "${DB_PASSWORD}"
}

# Command Usage: push
# Command Description: Docker push image to AWS ECR 
command_push() {
  echo "> Building docker image for service: $SERVICE_NAME"
  docker build -t $SERVICE_NAME -f ./docker/Dockerfile .

  echo "> Tagging image from $SERVICE_NAME:latest to $ECR_REPO_URI:latest"
  docker tag $SERVICE_NAME:latest $ECR_REPO_URI:latest
  
  echo "> Login docker and push image to ECR"
  aws ecr get-login --no-include-email --region eu-west-1 | bash
  
  echo "> Pushing image $ECR_REPO_URI:latest"
  docker push $ECR_REPO_URI:latest
}

gradle_clean() {
  ./gradlew clean build -x test
}

check_msg() {
  printf "\xE2\x9C\x94 ${1}\n"
}

main() {
  [[ -z "${@}" ]] && eval set -- "--help"

  local theCommand=

  set_command() {
    [[ -z "${theCommand}" ]] || exit_err "Only one command at a time!"
    theCommand="${1}"
  }

  while (( ${#} )); do
    case "${1}" in

      --help|-h)
        option_help
        exit 0
        ;;

      --prod|-p)
        option_prod
        ;;

      run|test|clean|up|down|console|push)
        set_command "${1}"
        ;;

      *)
        PARAMETER="${1}"
        ;;
    esac

    shift 1
  done

  [[ ! -z "${theCommand}" ]] || exit_err "Command not found!"

  case "${theCommand}" in
    run) command_run;;
    test) command_test;;
    clean) command_clean;;
    up) command_up;;
    down) command_down;;
    console) command_console;;
    push) command_push;;

    *) option_help; exit 1;;
  esac
}

main "${@-}"
