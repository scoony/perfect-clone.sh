#!/bin/bash

#### Making sure no other process is running already
my_script=`basename "$0"`
if pidof -x "$my_script" >/dev/null; then
    echo "Process already running"
    exit 1
fi

#### Checking internet connection
ping -q -w1 -c1 google.com &>/dev/null && internet="Online" || internet="Offline"
if [[ $internet == "Offline" ]]; then
  echo "ERROR: This script requires internet"
  exit 1
fi

#### Config
local_folder="/opt/scripts/perfect-clone/"
mount_points="/mnt"
exclude_folders="/mnt/sdb1 /mnt/USB"
movie_tag="/Plex/Films/"
# PushOver config
token_app=""
destinataire_1=""
destinataire_2=""
titre_push=""


#### Requirements
dependencies="ffmpeg" ## Error with tools like mkvtoolnix (no bin with this name)

for req_dep in $dependencies; do
  if hash $req_dep 2>/dev/null; then
    echo -e "[OK] Dependency: $req_dep"
  else
    echo -e "[INSTALL] Dependency: $req_dep"
    OS_NAME=`lsb_release -si`
    if [[ $OS_NAME == "Ubuntu" ]]; then apt install $req_dep -y; fi
    if [[ $OS_NAME == "CentOS" ]]; then yum install $req_dep -y; fi
    if hash $req_dep 2>/dev/null; then
      echo -e "Please install manually $req_dep"
      pushmessage ()
      exit 1
    fi
  fi
done

#### Autoupdater
if [[ ! -d ${local_folder} ]]; then
  mkdir -p ${local_folder}
fi
remote_folder="https://raw.githubusercontent.com/scoony/perfect-clone.sh/main/"
 
source <(curl -s https://raw.githubusercontent.com/scoony/perfect-clone.sh/main/extras/update-files)

rm ${remote_folder}update-required
for current_file in $file{001..999}; do
  remote_md5=`curl -s ${remote_folder}$current_file | md5sum | cut -f1 -d" "`
  local_md5=`md5sum ${local_folder}$current_file 2>/dev/null | cut -f1 -d" "`
  if [[ $remote_md5 == $local_md5 ]]; then
    echo "$current_file : No upgrade required"
  else
    echo "$current_file : Upgrade required"
    if [[ "$current_file" == "$my_script" ]]; then
      wget --quiet "${remote_folder}${current_file}" -O "${local_folder}${current_file}.new"
      echo '#!/bin/bash' > ${remote_folder}update-required
      echo "mv -f ${local_folder}${current_file}.new ${local_folder}${current_file}" >> ${remote_folder}update-required
      echo "bash ${local_folder}${current_file}" >> ${remote_folder}update-required
      echo "exit 1" >> ${remote_folder}update-required
      read -t 3 -p "[UPDATE REQUIRED] $my_script will restart in 3s ..."
      bash ${remote_folder}update-required
      exit 1
    else
      wget --quiet "${remote_folder}${current_file}" -O "${local_folder}${current_file}"
      if [[ "$current_file" =~ ".sh" ]]; then
        chmod +x "${local_folder}${current_file}"
      fi
      echo "Update Done"
    fi
  fi
done

#### Arguments handled
[[ "$@" =~ '--full-scan-movie' ]] && arg_full_scan_movie=TRUE
[[ "$@" =~ '--full-scan-tv' ]] && arg_full_scan_tv=TRUE
[[ "$@" =~ '--filebot-movie' ]] && arg_filebot_movie=TRUE
[[ "$@" =~ '--filebot-tv' ]] && arg_filebot_tv=TRUE

#### Push message function (Pushover)
push-message() {
  push_title=$1
  push_content=$2
  for user in {1..10}; do
    destinataire=`eval echo "\\$destinataire_"$user`
    if [ -n "$destinataire" ]; then
      curl -s \
        --form-string "token=$token_app" \
        --form-string "user=$destinataire" \
        --form-string "title=$push_title" \
        --form-string "message=$push_content" \
        --form-string "html=1" \
        --form-string "priority=0" \
        https://api.pushover.net/1/messages.json > /dev/null
    fi
  done
}

#### Generate local DB
updatedb --output ${local_folder}source.db --database-root ${mount_points} --prunepaths="${exclude_folders}"

#### Display DB infos
locate -d ${local_folder}source.db -S

#### Create the databases (if not existing)
if [[ ! -f ${local_folder}my_medias.sqlite ]]; then
  sqlite3 ${local_folder}my_medias.sqlite "create table movies (id INTEGER PRIMARY KEY,filename TEXT,size TEXT,codec TEXT,languages TEXT,resolution TEXT,path TEXT,homemade TEXT,creation_time TEXT,imdb TEXT,tmdb TEXT,title_fr TEXT,title_en TEXT);"
fi

#### *_MOVIE ARGUMENT
if [[ $arg_full_scan_movie == TRUE ]] || [[ $arg_filebot_movie == TRUE ]]; then
  ## Create/Update the movies DB
  ## Get the full paths of my movies
  locate -d ${local_folder}source.db / | grep "${movie_tag}" > ${local_folder}movies.tmp
  ## Store the paths in a table
  movie_paths=()
  while IFS= read -r -d $'\0'; do
    movie_paths+=("$REPLY")
  done <${local_folder}movies.tmp
  rm -f ${local_folder}movies.tmp

  ## FULL_SCAN_MOVIE ARGUMENT
  if [[ $arg_full_scan_movie == TRUE ]]; then
    ## Store the infos in the db for each movies
    movie_count=0
    for movie in "${movie_paths[@]}"; do
      movie_filename_local=`basename ${movie}`
      movie_creation_local=`ffprobe -v quiet -show_entries format_tags=creation_time -of csv=p=0 ${movie}`
      db_check_filename=`sqlite3 ${local_folder}my_medias.sqlite "SELECT filename FROM movies WHERE filename=\"$movie_filename_local\"";`
      db_check_creation=`sqlite3 ${local_folder}my_medias.sqlite "SELECT filename FROM movies WHERE ceation_time=\"$movie_creation_local\"";`
      if [[ ! ${db_check_filename}]] && [[ ! ${db_check_creation} ]]; then
        if [[ ${movie} == *@(.mkv|.avi|.mp4) ]]; then
          movie_filename=`basename ${movie}`
          movie_size=`wc -c "${movie}" | awk '{print $1}'`
          movie_codec=`ffprobe -v quiet -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 ${movie}`
          movie_languages=`ffprobe -v quiet -show_entries stream=index:stream_tags=language -select_streams a -v 0 -of compact=p=0:nk=1 ${movie}`
          movie_resolution=`ffprobe -v quiet -select_streams v:0 -show_entries stream=width,height -of csv=p=0 ${movie}`
          ##movie_md5=`md5sum ${movie} 2>/dev/null | cut -f1 -d" "` ## takes too long (5s for a movie) replaced by creation_time
          movie_creation_time=`ffprobe -v quiet -show_entries format_tags=creation_time -of csv=p=0 ${movie}`
          printf "\rProgress: ${movie_count}/${#array[@]}" ## should be on the same line
          sqlite3 ${local_folder}my_medias.sqlite "insert into movies (filename,size,codec,language,resolution,path,creation_time) values (\"$movie_filename\",\"$movie_size\",\"$movie_codec\",\"$movie_languages\",\"$movie_resolution\",\"$movie\",\"$movie_creation_time\");"
          movie_count=$((movie_count+1))
        else
          ##echo -e "Bad File: ${movie}"
          pushmessage ()
          printf "\rProgress: ${movie_count}/${#array[@]}" ## should be on the same line
          movie_count=$((movie_count+1))
        fi
      else
        pushmessage "Potential dupe detected... skipped"
      fi
    done
  fi

  ## FILEBOT_MOVIE ARGUMENT
  if [[ $arg_filebot_movie == TRUE ]]; then
    movie_count=0
    for movie in "${movie_paths[@]}"; do ## or thru the db only
      filebot --action test -script fn:amc --db TheMovieDB -non-strict --conflict override --lang fr --encoding UTF-8 --mode rename "/opt/scripts/$movie" --def minFileSize=0 --def "movieFormat=/opt/scripts/TEMP/#0??{localize.English.n}#1??{localize.French.n}#2??{id}#3??{imdbid}#4??" 2>/dev/null > ${local_folder}filebot_movie.txt
      filebot_title_en=`cat ${local_folder}filebot_movie.txt | grep "TEST" | sed 's/.*#0??//' | sed 's/#1??.*//'`
      filebot_title_fr=`cat ${local_folder}filebot_movie.txt | grep "TEST" | sed 's/.*#1??//' | sed 's/#2??.*//'`
      filebot_tmdb_id=`cat ${local_folder}filebot_movie.txt | grep "TEST" | sed 's/.*#3??//' | sed 's/#4??.*//'`
      filebot_imdb_id=`cat ${local_folder}filebot_movie.txt | grep "TEST" | sed 's/.*#4??//' | sed 's/#5??.*//'`
      rm -f ${local_folder}filebot_movie.txt
      movie_count=$((movie_count+1))
    done
  fi
fi

#### FILEBOT_MOVIE ARGUMENT

#### Get remote DB
