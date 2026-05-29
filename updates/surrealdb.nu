#!/usr/bin/env nu

# Custom update script for surrealdb
# Fetches latest version from https://download.surrealdb.com/latest.txt

def main [pkgname: string] {
	let url = "https://download.surrealdb.com/latest.txt"

	let result = (
		try {
			http get $url
		} catch { |err|
			print -e $"::error::❌ Failed to fetch latest version from ($url): ($err.msg)"
			exit 1
		}
	)

	let ver = ($result | str trim | split row "\n" | first | str trim)

	# Strip 'v' prefix if present (e.g., "v3.1.2" -> "3.1.2")
	let ver = ($ver | str replace -r '^v' '')

	if ($ver | is-empty) or ($ver == "") {
		print -e "::error::❌ Empty version response from download.surrealdb.com"
		exit 1
	}

	$ver
}
