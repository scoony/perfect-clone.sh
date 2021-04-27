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
#### Arguments handled
[[ "$@" =~ '--full-scan-movie' ]] && arg_full_scan_movie=TRUE
[[ "$@" =~ '--full-scan-tv' ]] && arg_full_scan_tv=TRUE
[[ "$@" =~ '--filebot-movie' ]] && arg_filebot_movie=TRUE
[[ "$@" =~ '--filebot-tv' ]] && arg_filebot_tv=TRUE

#### Generate local DB
updatedb --output ${local_folder}source.db --database-root ${mount_points} --prunepaths="${exclude_folders}"

#### Display DB infos
locate -d ${local_folder}source.db -S

# Create the database for the movies (if not existing)
if [[ ! -f ${local_folder}my_medias.sqlite ]]; then
  sqlite3 ${local_folder}my_medias.sqlite "create table movies (id INTEGER PRIMARY KEY,filename TEXT,size TEXT,codec TEXT,languages TEXT,resolution TEXT,path TEXT,homemade TEXT,creation_time TEXT);"
fi

#### FULL_SCAN_MOVIE ARGUMENT
if [[ $arg_full_scan_movie == TRUE ]]; then
  ## FULL PROCESS: Create/Update the movies DB
  ## Get the full paths of my movies
  locate -d ${local_folder}source.db / | grep "${movie_tag}" > ${local_folder}movies.tmp
  ## Store the paths in a table
  movie_paths=()
  while IFS= read -r -d $'\0'; do
    movie_paths+=("$REPLY")
  done <${local_folder}movies.tmp
  rm -f ${local_folder}movies.tmp
  ## Store the infos in the db for each movies
  movie_count=0
  for movie in "${movie_paths[@]}"; do
    movie_filename_local=`basename ${movie}`
    movie_creation_local=`ffprobe -v quiet -show_entries format_tags=creation_time -of csv=p=0 ${movie}`
    db_check_filename=`sqlite3 ${local_folder}my_medias.sqlite "SELECT filename FROM movies WHERE filename=\"$movie_filename_local\"";`
    db_check_creation=`sqlite3 ${local_folder}my_medias.sqlite "SELECT filename FROM movies WHERE ceation_time=\"$movie_creation_local\"";`
    if [[ ! ${db_check_filename}]] && [[ ! ${db_check_creation} ]]; then
      if [[ ${movie} =~ (.mkv|.avi|.mp4) ]]; then
        movie_filename=`basename ${movie}`
        movie_size=`wc -c "${movie}" | awk '{print $1}'`
        movie_codec=`ffprobe -v quiet -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 ${movie}`
        movie_languages=`ffprobe -v quiet -show_entries stream=index:stream_tags=language -select_streams a -v 0 -of compact=p=0:nk=1 ${movie}`
        movie_resolution=`ffprobe -v quiet -select_streams v:0 -show_entries stream=width,height -of csv=p=0 ${movie}`
        ##movie_md5=`md5sum ${movie} 2>/dev/null | cut -f1 -d" "` ## takes too long (5s for a movie) replaced by creation_time
        movie_creation_time=`ffprobe -v quiet -show_entries format_tags=creation_time -of csv=p=0 ${movie}`
        printf "\rProgress: ${movie_count}/${#array[@]}" ## should be on the same line
        movie_count=$((movie_count+1))
      else
        ##echo -e "Bad File: ${movie}"
        pushmessage () ## To Do
        printf "\rProgress: ${movie_count}/${#array[@]}" ## should be on the same line
        movie_count=$((movie_count+1))
      fi
    else
      pushmessage "Potential dupe detected... skipped"
    fi
  done
fi

#### Get remote DB
