#!/bin/bash

# Note that this does not use pipefail because if the grep later
# doesn't match I want to be able to show an error first
set -eo

# Ensure SVN username and password are set
# IMPORTANT: while secrets are encrypted and not viewable in the GitHub UI,
# they are by necessity provided as plaintext in the context of the Action,
# so do not echo or use debug mode unless you want your secrets exposed!

# Allow some ENV variables to be customized
if [[ -z "$SLUG" ]]; then
	SLUG=${GITHUB_REPOSITORY#*/}
fi
echo "ℹ︎ SLUG is $SLUG"

if [[ -z "$ASSETS_DIR" ]]; then
	ASSETS_DIR=".wordpress-org"
fi
echo "ℹ︎ ASSETS_DIR is $ASSETS_DIR"

SVN_URL="http://plugins.svn.wordpress.org/${SLUG}/"
SVN_DIR="/github/svn-${SLUG}"

# Checkout just trunk and assets for efficiency
# Stable tag will come later, if applicable
echo "➤ Checking out .org repository..."
svn checkout --depth immediates "$SVN_URL" "$SVN_DIR"
cd "$SVN_DIR"
svn update --set-depth infinity assets
svn update --set-depth infinity trunk

echo "➤ Copying files..."
if [[ -e "$GITHUB_WORKSPACE/.distignore" ]]; then
	echo "ℹ︎ Using .distignore"
	# Copy from current branch to /trunk, excluding dotorg assets
	# The --delete flag will delete anything in destination that no longer exists in source
	rsync -rc --exclude-from="$GITHUB_WORKSPACE/.distignore" "$GITHUB_WORKSPACE/" trunk/ --delete
else
	echo "ℹ︎ Using .gitattributes"

	cd "$GITHUB_WORKSPACE"

	# "Export" a cleaned copy to a temp directory
	TMP_DIR="/github/archivetmp"
	mkdir "$TMP_DIR"

	git config --global user.email "10upbot+github@10up.com"
	git config --global user.name "10upbot on GitHub"

	# If there's no .gitattributes file, write a default one into place
	if [[ ! -e "$GITHUB_WORKSPACE/.gitattributes" ]]; then
		cat > "$GITHUB_WORKSPACE/.gitattributes" <<-EOL
		/$ASSETS_DIR export-ignore
		/.gitattributes export-ignore
		/.gitignore export-ignore
		/.github export-ignore
		EOL

		# Ensure we are in the $GITHUB_WORKSPACE directory, just in case
		# The .gitattributes file has to be committed to be used
		# Just don't push it to the origin repo :)
		git add .gitattributes && git commit -m "Add .gitattributes file"
	fi

	# This will exclude everything in the .gitattributes file with the export-ignore flag
	git archive HEAD | tar x --directory="$TMP_DIR"

	cd "$SVN_DIR"

	# Copy from clean copy to /trunk, excluding dotorg assets
	# The --delete flag will delete anything in destination that no longer exists in source
	rsync -rc "$TMP_DIR/" trunk/ --delete
fi

# Copy dotorg assets to /assets
rsync -rc "$GITHUB_WORKSPACE/$ASSETS_DIR/" assets/ --delete

echo "➤ Preparing files..."

svn status

# if [[ -z $(svn stat) ]]; then
# 	echo "🛑 Nothing to deploy!"
# 	exit 0
# Check if there is more than just the readme.txt modified in trunk
# The leading whitespace in the pattern is important
# so it doesn't match potential readme.txt in subdirectories!
# elif svn stat trunk | grep -qvi ' trunk/readme.txt$'; then
# 	echo "🛑 Other files have been modified; changes not deployed"
# 	exit 1
# fi

# Readme also has to be updated in the .org tag
echo "➤ Preparing stable tag..."
echo $TMP_DIR