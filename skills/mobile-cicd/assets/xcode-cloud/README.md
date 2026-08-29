# ci_scripts templates

Copy the stack folder's three `ci_*.sh` files plus `common/notify.sh` into the project's `ci_scripts/` directory
(`ios/ci_scripts/` for Flutter and React Native; next to the `.xcodeproj` for native). All four files must sit in the
same directory — the scripts `source "$SCRIPT_DIR/notify.sh"`.

After copying:

    git add <dir>/ci_scripts
    git update-index --chmod=+x <dir>/ci_scripts/*.sh
    cat assets/gitattributes-snippet >> .gitattributes
    scripts/check_ci_scripts.sh .

`ci_post_xcodebuild.sh` is identical across stacks (it only reads `pubspec.yaml` if present).
