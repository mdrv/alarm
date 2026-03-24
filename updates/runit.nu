#!/usr/bin/env nu

# Custom update script for runit (smarden.org)
# Parses version from https://smarden.org/runit/install

def get_version [pkgname: string] {
    let pkg_short = ($pkgname | str replace -r "-git$" "")
    let install_url = $"https://smarden.org/($pkg_short)/install"

    let html = (
        try {
            http get $install_url
        } catch { |err|
            print -e $"::warning::⚠️ Failed to fetch install page for ($pkgname)"
            return null
        }
    )

    # Extract version using string operations
    # Find the tar.gz filename and parse out version
    for line in ($html | lines) {
        if ($line | str contains $"($pkg_short)-") and ($line | str contains ".tar.gz") {
            # Extract the tar.gz filename
            let filename = ($line | split row "href=" | get 1 | split row '"' | get 1)
            
            # Parse version: pkgname-X.Y.Z.tar.gz -> X.Y.Z
            let ver = ($filename | split row "-" | get 1 | split row "." | take 3 | str join ".")
            
            return $ver
        }
    }

    print -e $"::warning::⚠️ Could not parse version from install page"
    return null
}

def main [pkgname: string] {
    let version = (get_version $pkgname)
    if $version == null {
        exit 1
    }
    $version
}
