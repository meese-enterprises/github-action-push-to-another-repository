#!/bin/bash -l

set -e  # if a command fails it stops the execution
set -u  # script fails if trying to access to an undefined variable

echo ""
echo "[+] Action start"
SOURCE_DIRECTORIES="${1}"
DESTINATION_DIRECTORY_PREFIXES="${2}"
DESTINATION_GITHUB_USERNAME="${3}"
DESTINATION_REPOSITORY_NAME="${4}"
GITHUB_SERVER="${5}"
USER_EMAIL="${6}"
USER_NAME="${7}"
DESTINATION_REPOSITORY_USERNAME="${8}"
TARGET_BRANCH="${9}"
COMMIT_MESSAGE="${10}"
TARGET_DIRECTORY="${11}"
FORCE="${12}"

if [ -z "$DESTINATION_REPOSITORY_USERNAME" ]
then
	DESTINATION_REPOSITORY_USERNAME="$DESTINATION_GITHUB_USERNAME"
fi

if [ -z "$USER_NAME" ]
then
	USER_NAME="$DESTINATION_GITHUB_USERNAME"
fi

DESTINATION_REPOSITORY="$DESTINATION_REPOSITORY_USERNAME/$DESTINATION_REPOSITORY_NAME"
TARGET_BRANCH_EXISTS=true

# Verify that there (potentially) some access to the destination repository
# and set up git (with GIT_CMD variable) and GIT_CMD_REPOSITORY
if [ -n "${SSH_DEPLOY_KEY:=}" ]
then
	# Inspired by https://github.com/leigholiver/commit-with-deploy-key/blob/main/entrypoint.sh, thanks!
	mkdir --parents "$HOME/.ssh"
	DEPLOY_KEY_FILE="$HOME/.ssh/deploy_key"
	echo "${SSH_DEPLOY_KEY}" > "$DEPLOY_KEY_FILE"
	chmod 600 "$DEPLOY_KEY_FILE"

	SSH_KNOWN_HOSTS_FILE="$HOME/.ssh/known_hosts"
	ssh-keyscan -H github.com > "$SSH_KNOWN_HOSTS_FILE"

	export GIT_SSH_COMMAND="ssh -i "$DEPLOY_KEY_FILE" -o UserKnownHostsFile=$SSH_KNOWN_HOSTS_FILE"

	GIT_CMD_REPOSITORY="git@$GITHUB_SERVER:$DESTINATION_REPOSITORY.git"

elif [ -n "${API_TOKEN_GITHUB:=}" ]
then
	GIT_CMD_REPOSITORY="https://$DESTINATION_REPOSITORY_USERNAME:$API_TOKEN_GITHUB@$GITHUB_SERVER/$DESTINATION_REPOSITORY.git"
else
	echo "[-] API_TOKEN_GITHUB and SSH_DEPLOY_KEY are empty. Please fill one in!"
	exit 1
fi

CLONE_DIR=$(mktemp -d)

echo "[+] Git version"
git --version

# Setup git
git config --global user.email "$USER_EMAIL"
git config --global user.name "$USER_NAME"

echo ""
echo "[+] Cloning destination git repository $DESTINATION_REPOSITORY_NAME"
{
	git clone --single-branch --depth 1 --branch "$TARGET_BRANCH" "$GIT_CMD_REPOSITORY" "$CLONE_DIR"
} || {
	{
		echo "Target branch doesn't exist, fetching the 'main' branch"
		git clone --single-branch "https://$USER_NAME:$API_TOKEN_GITHUB@$GITHUB_SERVER/$DESTINATION_REPOSITORY.git" "$CLONE_DIR"
		TARGET_BRANCH_EXISTS=false
	} || {
		echo ""
		echo "[-] Could not clone the destination repository. Command:"
		echo "[-] git clone --single-branch --depth 1 --branch $TARGET_BRANCH $GIT_CMD_REPOSITORY $CLONE_DIR"
		echo "[-] (Note that if they exist, USER_NAME and API_TOKEN are redacted by GitHub)"
		echo "[-] Please verify that the target repository exist AND that it contains the destination branch name, and is accesible by the API_TOKEN_GITHUB OR SSH_DEPLOY_KEY"
		exit 1
	}
}

echo ""
echo "[+] Listing the contents of the clone directory:"
ls -la "$CLONE_DIR"

TEMP_DIR=$(mktemp -d)
# This mv has been the easier way to be able to remove files that were there
# but not anymore. Otherwise we had to remove the files from "$CLONE_DIR",
# including "." and with the exception of ".git/"
mv "$CLONE_DIR/.git" "$TEMP_DIR/.git"

# $TARGET_DIRECTORY is '' by default
ABSOLUTE_TARGET_DIRECTORY="$CLONE_DIR/$TARGET_DIRECTORY/"

echo ""
echo "[+] Deleting $ABSOLUTE_TARGET_DIRECTORY"
rm -rf "$ABSOLUTE_TARGET_DIRECTORY"

echo ""
echo "[+] Creating (now empty) $ABSOLUTE_TARGET_DIRECTORY"
mkdir -p "$ABSOLUTE_TARGET_DIRECTORY"

mv "$TEMP_DIR/.git" "$CLONE_DIR/.git"

# https://stackoverflow.com/a/42399738/6456163
set +e
NUM_SOURCE_DIRS=$(echo -n "$SOURCE_DIRECTORIES" | grep -c '^')
NUM_DEST_PREFIXES=$(echo -n "$DESTINATION_DIRECTORY_PREFIXES" | grep -c '^')
if [ "$NUM_DEST_PREFIXES" -ne 0 ] && [ "$NUM_SOURCE_DIRS" -ne "$NUM_DEST_PREFIXES" ]
then
	echo ""
	echo "[-] The number of source directories ($NUM_SOURCE_DIRS) is different from the number of destination directory prefixes ($NUM_DEST_PREFIXES)"
	exit 1
fi
set -e

# Parses the passed strings to arrays and removes the leading `[` from the YAML parsing
# https://stackoverflow.com/a/5257398/6456163
SOURCE_DIRECTORIES_ARRAY=(${SOURCE_DIRECTORIES//\\n/ })
SOURCE_DIRECTORIES_ARRAY[0]="${SOURCE_DIRECTORIES_ARRAY[0]:1}"

if [ -n "${DESTINATION_DIRECTORY_PREFIXES:=}" ]
then
	DESTINATION_DIRECTORY_PREFIXES_ARRAY=(${DESTINATION_DIRECTORY_PREFIXES//\\n/ })
	DESTINATION_DIRECTORY_PREFIXES_ARRAY[0]="${DESTINATION_DIRECTORY_PREFIXES_ARRAY[0]:1}"
else
	# Populate an array of the correct length with empty strings
	for i in $(seq "$NUM_SOURCE_DIRS"); do
		DESTINATION_DIRECTORY_PREFIXES_ARRAY[$i]=""
	done
fi

# Loop over all the directories and copy them to the right destination
for i in $(seq "$NUM_SOURCE_DIRS"); do
	SOURCE_DIRECTORY="${SOURCE_DIRECTORIES_ARRAY[$i]}"
	DESTINATION_DIRECTORY_PREFIX="${DESTINATION_DIRECTORY_PREFIXES_ARRAY[$i]}"

	echo ""
	echo "[+] Copying $SOURCE_DIRECTORY to $ABSOLUTE_TARGET_DIRECTORY$DESTINATION_DIRECTORY_PREFIX"
	cp -r "$SOURCE_DIRECTORY" "$ABSOLUTE_TARGET_DIRECTORY$DESTINATION_DIRECTORY_PREFIX"
done

# Loop over all the directories and copy them to the destination
for SOURCE_DIRECTORY in $SOURCE_DIRECTORIES
do
	if [ ! -d "$SOURCE_DIRECTORY" ]
	then
		echo ""
		echo "[+] Source directory $SOURCE_DIRECTORY does not exist, skipping"
		continue
	fi

	echo ""
	echo "[+] List contents of $SOURCE_DIRECTORY:"
	ls -la "$SOURCE_DIRECTORY"

	echo ""
	echo "[+] Copying contents of source repository folder '$SOURCE_DIRECTORY' to git repo '$DESTINATION_REPOSITORY_NAME'"
	cp -ra "$SOURCE_DIRECTORY"/. "$CLONE_DIR/$TARGET_DIRECTORY"
done

cd "$CLONE_DIR"
echo ""
echo "[+] List of files that will be pushed:"
ls -la

# Used for local testing, when ran via `./entrypoint.sh [...]`
# GITHUB_REPOSITORY="$DESTINATION_REPOSITORY_USERNAME/$DESTINATION_REPOSITORY_NAME"
# GITHUB_SHA="$(git rev-parse HEAD)"
# GITHUB_REF="refs/heads/$TARGET_BRANCH"

ORIGIN_COMMIT="https://$GITHUB_SERVER/$GITHUB_REPOSITORY/commit/$GITHUB_SHA"
COMMIT_MESSAGE="${COMMIT_MESSAGE/ORIGIN_COMMIT/$ORIGIN_COMMIT}"
COMMIT_MESSAGE="${COMMIT_MESSAGE/\$GITHUB_REF/$GITHUB_REF}"

if [ "$TARGET_BRANCH_EXISTS" = false ]; then
	echo ""
  echo "Creating branch $TARGET_BRANCH"
  git checkout -b "$TARGET_BRANCH"
fi

# Related to https://github.com/cpina/github-action-push-to-another-repository/issues/64
# and https://github.com/cpina/github-action-push-to-another-repository/issues/64
echo ""
echo "[+] Set directory as safe ($CLONE_DIR)"
git config --global --add safe.directory "$CLONE_DIR"

echo ""
echo "[+] Adding git commit"
git add .

echo ""
echo "[+] git status:"
git status

# git diff-index: avoids the git commit failing if there are no changes
echo ""
echo "[+] git diff-index:"
git diff-index --quiet HEAD || git commit --message "$COMMIT_MESSAGE"

# --set-upstream: sets de branch when pushing to a branch that does not exist
echo ""
if [ "$FORCE" = true ]; then
  echo "[+] Forcefully pushing git commit"
	git push -f "$GIT_CMD_REPOSITORY" --set-upstream "$TARGET_BRANCH"
else
  echo "[+] Pushing git commit"
  git push "$GIT_CMD_REPOSITORY" --set-upstream "$TARGET_BRANCH"
fi
