#/bin/bash
base_dir=~/src/work

new_token=`pbpaste | sed 's/access_token: //'`

# Check that past buffer contains something that looks a JWT token, fail if not
case ${new_token:0:3} in
  eyJ)
    ;;
  *)
    echo "Token is not encoded JSON! (starts with: '${new_token:0:15}...')"
    exit 3
    ;;
esac

session_base_name='session.service.ts'

# the session files can be in slightly different places, check around for them.
session_files=`find ${base_dir}/common-platform*/*/src/app -iname ${session_base_name}`

case $session_files in
  "")
    echo 1>&2 "? No session files found when searching or '${session_base_name}' not found!"
    exit 5
    ;;
esac

# echo "new token tail:       ${new_token: -10}"

first_pass=true
date
for session_file in ${session_files}
do
  # Create a new token-line
  token_line=`sed  -n "/accessToken:/s/.*/${new_token}/p" ${session_file}`
  case $first_pass in
    true)
      echo "new accessToken tail:     ${token_line: -10}"
      first_pass=false
      ;;
  esac

  # Actually make the token replacement
  # Note: sometimes the file has the token on a separate line from the `accessToken:` tag
  # so we concatenate the line following and substitute everything within the first single
  # quote pair.
  echo "Replacing token in $session_file" | sed "s=${base_dir}/=="
  sed -i "" "/'testAccessToken'/s//'${new_token}'/; /eyJ/s/'eyJ.*'/'${new_token}'/" ${session_file}

  # Sed won't fail if no substitution is made, so we explicitly check for the replacement
  grep --silent "${new_token}" ${session_file} || {
    echo 1>&2 "? Stream edit failed: Token NOT replaced"
      exit 4
    }
done

