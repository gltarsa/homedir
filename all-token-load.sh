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

date
for session_file in ${session_files}
do
  repo_dir=`echo "$session_file" | sed 's=/src/app.*=='`
  (cd $repo_dir; load-token)
done

