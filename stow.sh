#!/bin/sh
for dir in */; do
	stow "$dir"
done
