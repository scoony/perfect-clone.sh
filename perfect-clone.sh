#!/bin/bash

#### Requirements ffmpeg

#### Config
mount_points="/mnt"
exclude_folders="/mnt/sdb1 /mnt/USB"
movie_tag="/Plex/Films/"


#### Autoupdater
remote_folder="https://raw.githubusercontent.com/scoony/perfect-clone.sh/main/"
local_folder="/opt/scripts/perfect-clone/"
 
source <(curl -s https://raw.githubusercontent.com/scoony/perfect-clone.sh/main/extras/update-files)
 
for current_file in $file{001..999}; do
  remote_md5=`curl -s ${remote_folder}$current_file | md5sum | cut -f1 -d" "`
  local_md5=`md5sum ${local_folder}$current_file 2>/dev/null | cut -f1 -d" "`
  if [[ $remote_md5 == $local_md5 ]]; then
    echo "$current_file : No upgrade required"
  else
    echo "$current_file : Upgrade required"
    wget --quiet "${remote_folder}${current_file}" -O "${local_folder}${current_file}"
    if [[ "$current_file" =~ ".sh" ]]; then
      chmod +x "${local_folder}${current_file}"
    fi
    echo "Update Done"
  fi
done

#### Generate local DB
updatedb --output ${local_folder}source.db --database-root ${mount_points} --prunepaths="${exclude_folders}"

#### Display DB infos
locate -d ${local_folder}source.db -S

#### Create/Update the movies DB
## Get the full paths of my movies
locate -d ${local_folder}source.db / | grep "${movie_tag}" > ${local_folder}movies.tmp
## Store the paths in a table
movie_paths=()
while IFS= read -r -d $'\0'; do
  movie_paths+=("$REPLY")
done <${local_folder}movies.tmp
rm -f ${local_folder}movies.tmp
## Create the database for the movies (if not existing)
if [[ ! -f ${local_folder}my_medias.sqlite ]]; then
  sqlite3 ${local_folder}my_medias.sqlite "create table movies (id INTEGER PRIMARY KEY,filename TEXT,size TEXT,codec TEXT,languages TEXT,resolution TEXT,path TEXT,homemade TEXT,md5 TEXT);"
fi
## Store the infos in the db for each movies
for movie in "${movie_paths[@]}; do
  movie_filename=`basename ${movie}`
  movie_size=`wc -c "${movie}" | awk '{print $1}'`
  movie_codec=`ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 ${movie}`
  movie_languages=`ffprobe -show_entries stream=index:stream_tags=language -select_streams a -v 0 -of compact=p=0:nk=1 ${movie}`
  movie_resolution=`ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 ${movie}`
  movie_md5=`md5sum ${movie} 2>/dev/null | cut -f1 -d" "` ## takes too long (5s for a movie)
done

#### Get remote DB
