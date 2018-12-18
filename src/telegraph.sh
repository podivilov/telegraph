#!/bin/bash

#
# Telegraph
# (c) 2018 Mihail Podivilov
#
# See copyright notice in LICENSE
#

# Enable ignoring of failed matches
shopt -s nullglob

# Enable extended pattern matching
shopt -s extglob

#
# System variables
#

# Copyright information
AUTHOR="Mihail Podivilov"
VERSION="0.13.1"
YEAR="`date +%Y`"

# Terminal-specific variables
COUNTRY_ID="1"                # Russia
ZONE_ID="0455"                # Kolomna
TERMINAL_ID="00"              # Terminal ID
TERMINAL_UID="0000"           # Terminal UID
TGPATH="/root/TELEGRAPH"      # Telegraph working directory
MOUNTPATH="/mnt"              # Mount path

# Enable sound notifications
ENABLE_SOUND="1"

# Enable debug mode
DEBUG="0"

#
# Functions
#

# Play beep sound sequence to notify user
function beep() {
  # Only if sound notifications is enabled
  if [[ "$ENABLE_SOUND" == "1" ]]; then
    # Generate sequence of beeps, which count provided by $1 argument
    seq "$1" | xargs -Iz aplay /usr/share/telegraph/sounds/beep.wav &> /dev/null
  fi
}

# Log events to console window
function log() {
  if [[ "$DEBUG" == "1" ]] && [[ "${1^^}" == "DEBUG" ]]; then
    echo -e "[`date +%H:%M:%S` \e[101m${1^^}\e[0m]: ${@:2}"
  elif [[ "${1^^}" == "NOTICE" ]] || [[ "${1^^}" == "INFO" ]]; then
    echo -e "[`date +%H:%M:%S` ${1^^}]: ${@:2}"
  elif [[ "${1^^}" == "ERROR" ]]; then
    echo -e "[`date +%H:%M:%S` \e[101m${1^^}\e[0m]: ${@:2}"
  fi
}

#
# All the fun ahead...
#

# Print information about copyright
echo -e "\nTelegraph $VERSION  Copyright (C) $YEAR $AUTHOR\n"

# Check if we are running from non-root user
if [[ "$UID" != "0" ]]; then
  log error "Must be run from root user. Giving up!"; beep 8 &
  exit 1
fi

# Set DEVICE variable with flash device path
for sysdevpath in $(find /sys/bus/usb/devices/usb*/ -name dev); do
    (
        syspath="${sysdevpath%/dev}"
        device="$(udevadm info -q name -p $syspath)"
        [[ "$device" == "bus/"* ]] && continue
        eval "$(udevadm info -q property --export -p $syspath)"
        [[ -z "$ID_SERIAL" ]] && continue
        echo "/dev/$device" > /tmp/device
    )
done

# Set $DEVICE with /tmp/device contents
DEVICE="`cat /tmp/device`"; rm -f /tmp/device

# If there is no valid device were found
if [[ -z "$(lsblk $DEVICE 2>/dev/null)" ]]; then
  log error "No valid device found. Giving up!"; beep 8 &
  exit 1
fi

# Set $DEVICE_UUID with info, provided by lsblk
DEVICE_UUID="`lsblk $DEVICE --output UUID | sed -n 2p`"

# If DEVICE_UUID is empty
if [[ -z "$DEVICE_UUID" ]]; then
  log error "Device UUID is empty. Giving up!"; beep 8 &
  exit 1
fi

# If $DEVICE is a valid Telegraph device
if blkid -d | grep -q "$DEVICE: LABEL=\"TELEGRAPH\"" && [[ -f "$TGPATH/UUID/$DEVICE_UUID.TG" ]]; then

  # 1. Prepare the device
  # 1.1. Force to create $MOUNTPATH
  # 1.2. Force to unmount $DEVICE
  # 1.3. Mount $DEVICE to $MOUNTPATH
  # 1.4. Remove all but Telegraph files

  # Go!
  log notice "Setting up a $DEVICE..."; beep 1 &

  # Sleep 1 second for proper sound representation
  sleep 1

  # Set device type flag
  if [[ "$DEVICE_UUID" != "FFFF-FFFF" ]]; then
    # Common device type
    DEVICE_TYPE="COMMON"
  else
    # POSTMAN device type
    DEVICE_TYPE="POSTMAN"
  fi

  # Force to create $MOUNTPATH
  mkdir "$MOUNTPATH" &> /dev/null

  # Force to unmount $DEVICE
  umount -f "$DEVICE" &> /dev/null

  # Mount $DEVICE to $MOUNTPATH
  mount "$DEVICE" "$MOUNTPATH" &> /dev/null

  # Set TGPWD
  TGPWD=$(pwd)

  # If this device is a common device
  if [[ "$DEVICE_TYPE" == "COMMON" ]]; then
    # Remove all but common device Telegraph files
    cd "$MOUNTPATH"        > /dev/null 2>&1; rm -rf !(INBOX|OUTBOX|SYSTEM.TG);
    cd "$MOUNTPATH/INBOX"  > /dev/null 2>&1; rm -rf !(*.TG);
    cd "$MOUNTPATH/OUTBOX" > /dev/null 2>&1; rm -rf !(*.TG);
    cd "$TGPWD"
  # If this device is a POSTMAN device
  else
    # Remove all but POSTMAN device Telegraph files
    cd "$MOUNTPATH"        > /dev/null 2>&1; rm -rf !(POSTMAN|SYSTEM.TG);
    cd "$TGPWD"
  fi

  # If $DEVICE has label TELEGRAPH,
  # but there is no SYSTEM.TG file in root,
  # force to exit and notify user
  if [[ ! -f "$MOUNTPATH/SYSTEM.TG" ]]; then
    # Force to unmount the device
    umount -f "$DEVICE" &> /dev/null

    # Notify user about we are encountered unexpected error
    log error "No SYSTEM.TG were found on device. Giving up!"; beep 8 &
    exit 1
  fi

  # If this device is a POSTMAN device
  if [[ "$DEVICE_TYPE" == "POSTMAN" ]]; then
    # Get postman device ID from $MOUNTPATH/SYSTEM.TG
    ID=$(cat "$MOUNTPATH/SYSTEM.TG" | sed -n 2p | cut -d "=" -f2 | tr -d '\r')

    # Check if destination terminal ID is correct
    if [[ "`echo -n \"$ID\" | wc -c`" != "11" ]]; then
      # Force to unmount the device
      umount -f "$DEVICE" &> /dev/null

      # Notify user about we are encountered unexpected error
      log error "POSTMAN device found, but it's ID seems isn't set properly. Giving up!"; beep 8 &
      exit 1
    fi

    # For equals check
    ORIGIN_ID=$(cat "$MOUNTPATH/SYSTEM.TG" | sed -n 2p | cut -d "=" -f2)

    # Set ORIGIN_TERMINAL_ID variable
    ORIGIN_TERMINAL_ID=$(echo "$ID" | cut -c1-7)"0000"

    # Check POSTMAN identity
    POSTMAN_SECRET=$(cat "$MOUNTPATH/SYSTEM.TG"                 | sed -n 3p | cut -d "=" -f2)
    ORIGIN_POSTMAN_SECRET=$(cat "$TGPATH/UUID/$DEVICE_UUID.TG" | sed -n 3p | cut -d "=" -f2)

    # If this POSTMAN device is origin POSTMAN device
    # for this terminal
    if [[ "$POSTMAN_SECRET" == "$ORIGIN_POSTMAN_SECRET" ]]; then
      log notice "Origin POSTMAN device found."
      # Check if the $MOUNTPATH/POSTMAN directory exists and not empty
      if [[ ! -z "$(ls -A $MOUNTPATH/POSTMAN 2>/dev/null)" ]]; then
        # Copy ingoing mail to $TGPATH/MESSAGES/INGOING
        cp -rf "$MOUNTPATH/POSTMAN"* "$TGPATH/MESSAGES/INGOING"

        # Remove all ingoing messages for $MOUNTPATH/POSTMAN/*
        rm -rf "$MOUNTPATH/POSTMAN/"*

        # Force to unmount POSTMAN device
        umount -f "$DEVICE" &> /dev/null

        # Notify user about success
        log notice "Copied ingoing mail."
      else
        # Force to unmount POSTMAN device
        umount -f "$DEVICE" &> /dev/null

        # Notify user about there is no ingoing mail found
        log error "No ingoing mail found."; beep 8 &
        exit 1
      fi
    else
      log notice "Not origin POSTMAN device found."
      if [[ ! -z "$(ls -A $TGPATH/MESSAGES/OUTGOING/$ORIGIN_TERMINAL_ID 2>/dev/null)" ]]; then
        # Force to create POSTMAN directory
        mkdir -p "$MOUNTPATH/POSTMAN"

        # Copy all outgoing messages to POSTMAN directory
        cp -rf "$TGPATH/MESSAGES/OUTGOING/$ORIGIN_TERMINAL_ID/"* "$MOUNTPATH/POSTMAN"

        # Remove all outgoing messages for $ORIGIN_TERMINAL_ID
        rm -rf "$TGPATH/MESSAGES/OUTGOING/$ORIGIN_TERMINAL_ID"

        # Force to unmount POSTMAN device
        umount -f "$DEVICE" &> /dev/null

        # Notify user about success
        log notice "Copied outgoing mail to POSTMAN directory."; beep 2 &
        exit 0
      else
        # Force to unmount POSTMAN device
        umount -f "$DEVICE" &> /dev/null

        # Notify user about there is no outgoing messages found
        log error "No outgoing messages found for POSTMAN device terminal. Giving up!"; beep 8 &
        exit 1
      fi
    fi
  fi

  # If $DEVICE has label TELEGRAPH,
  # and there is SYSTEM.TG file presented in root,
  # but SECRET is not correct
  # (not set or not equals to original SECRET of user ID in root),
  # force to exit and notify user
  USER_SECRET=$(cat "$MOUNTPATH/SYSTEM.TG"          | sed -n 3p | cut -d "=" -f2)
  REAL_SECRET=$(cat "$TGPATH/UUID/$DEVICE_UUID.TG" | sed -n 3p | cut -d "=" -f2)

  if [[ "$USER_SECRET" != "$REAL_SECRET" ]]; then
    # Force to unmount the device
    umount -f "$DEVICE" &> /dev/null

    # Notify user about we are encountered unexpected error
    log error "Incorrect SECRET for this device were found in SYSTEM.TG. Giving up!"; beep 8 &
    exit 1
  fi

  # If all is okay, get ID from $MOUNTPATH/SYSTEM.TG
  ID=$(cat "$MOUNTPATH/SYSTEM.TG" | sed -n 2p | cut -d "=" -f2 | tr -d '\r')

  # For equals check
  ORIGIN_ID=$(cat "$MOUNTPATH/SYSTEM.TG" | sed -n 2p | cut -d "=" -f2)

  # Check OUTBOX folder in $MOUNTPATH/OUTBOX
  # for outgoing messages. Skip, if there is
  # no new outgoing messages are presented
  if [[ ! -z "$(ls -A $MOUNTPATH/OUTBOX 2>/dev/null)" ]]; then

    #
    # Check parameters for every file, such as:
    #
    # 1. Size in bytes. Can't be more than 65535 bytes
    # 2. Is the file name correct? 11 numbers + wildcard + dot + TG extension
    # 3. Does the recipient attached to this terminal?
    #

    for FILE in "$MOUNTPATH/OUTBOX/"*.TG; do
      # Get size of file, recipient number
      # and number length
      SIZE=$(stat -c %s "$FILE")
      NUMBER=$(basename "$FILE" | cut -c1-11)
      NUMBER_LENGTH=$(echo -n "$NUMBER" | wc -c)

      # If size less or equal to 65535 bytes
      # AND
      # File name is correct
      # AND
      # Recipient attached to this terminal
      if [[ "$SIZE" -le 65535 && "$NUMBER" =~ ^[0-9]+$ && "$NUMBER_LENGTH" == "11" ]]; then
        # Does recipient attached to this terminal?
        if [[ -d "$TGPATH/MESSAGES/INGOING/$NUMBER" ]]; then
          # Is the recipient ID is not equal to sender ID?
          if [[ "$NUMBER" == "$ORIGIN_ID" ]]; then
            # +1 to skipped files counter
            ((SKIPPED_FILES++))
          else
            # +1 to correct files counter
            ((CORRECT_FILES++))

            # Copy this file to $TGPATH/MESSAGES/INGOING
            SUFFIX_NUMBER="0"
            while test -e "$TGPATH/MESSAGES/INGOING/$NUMBER/$ID$SUFFIX".TG; do
              ((++SUFFIX_NUMBER))
              SUFFIX="$(printf -- ' (%d)' "$SUFFIX_NUMBER")"
            done
            cp "$FILE" "$TGPATH/MESSAGES/INGOING/$NUMBER/$ID$SUFFIX".TG

            # Remove this file from OUTBOX of user
            rm "$FILE"
          fi
        else
          # Set FULL_TERMINAL_ID variable
          FULL_TERMINAL_ID="$COUNTRY_ID$ZONE_ID$TERMINAL_ID$TERMINAL_UID"

          # Set ORIGIN_TERMINAL_ID variable
          ORIGIN_TERMINAL_ID=$(echo "$NUMBER" | cut -c1-7)"0000"

          # Is this user terminal ID equals to this terminal ID,
          # but doesn't have a folder?
          if [[ "$FULL_TERMINAL_ID" == "$ORIGIN_TERMINAL_ID" ]]; then
            # +1 to skipped files counter
            ((SKIPPED_FILES++))
          else
            # +1 to correct files counter
            ((CORRECT_FILES++))

            # Force to create $TGPATH/MESSAGES/OUTGOING/$ORIGIN_TERMINAL_ID/$NUMBER
            mkdir -p "$TGPATH/MESSAGES/OUTGOING/$ORIGIN_TERMINAL_ID/$NUMBER" &> /dev/null

            # Copy this file to $TGPATH/MESSAGES/OUTGOING/$ORIGIN_TERMINAL_ID/$NUMBER
            SUFFIX_NUMBER="0"
            while test -e "$TGPATH/MESSAGES/OUTGOING/$ORIGIN_TERMINAL_ID/$NUMBER/$ID$SUFFIX".TG; do
              ((++SUFFIX_NUMBER))
              SUFFIX="$(printf -- ' (%d)' "$SUFFIX_NUMBER")"
            done
            cp "$FILE" "$TGPATH/MESSAGES/OUTGOING/$ORIGIN_TERMINAL_ID/$NUMBER/$ID$SUFFIX".TG

            # Remove this file from OUTBOX of user
            rm "$FILE"
          fi
        fi
      else
        # +1 to skipped files counter
        ((SKIPPED_FILES++))
      fi
    done

    # If there are all files are correct
    if   [[ "$CORRECT_FILES" -ge "1" && "$SKIPPED_FILES" -eq "0" ]]; then
      # Notify user about sent files count
      log info "Successfully sent $CORRECT_FILES letter(-s)."
    # If there are at least one file are correct
    # and skipped files are present
    elif [[ "$CORRECT_FILES" -ge "1" && "$SKIPPED_FILES" -ge "1" ]]; then
      # Notify user that not all files were been sent
      SUFFIX_NUMBER="0"
      while test -e "$MOUNTPATH/INBOX/$COUNTRY_ID$ZONE_ID$TERMINAL_ID$TERMINAL_UID$SUFFIX".TG; do
        ((++SUFFIX_NUMBER))
        SUFFIX="$(printf -- ' (%d)' "$SUFFIX_NUMBER")"
      done
      printf "Уважаемый пользователь!\r\n\r\nНам не удалось произвести отправку одного или нескольких сообщений, которые были расположены в директории OUTBOX.\r\n\r\nПожалуйста, убедитесь в том, что:\r\n\r\n  * Файл сообщения имеет расширение .TG\r\n  * Объём сообщения не превышает 65535 символов\r\n  * Указан правильный номер получателя письма\r\n  * Вы отправляете сообщение не самому себе\r\n\r\nОбратите внимание: все недоставленные письма всё ещё находятся в директории OUTBOX. Вы можете попытаться исправить ошибки и повторить отправку.\r\n\r\n--\r\nЭто сообщение было сгенерировано автоматически.\r\nПожалуйста, не отвечайте на него.\r\n" > "$MOUNTPATH/INBOX/$COUNTRY_ID$ZONE_ID$TERMINAL_ID$TERMINAL_UID$SUFFIX".TG

      # Notify user about skipped files count
      log info "Successfully sent $CORRECT_FILES letter(-s) and skipped $SKIPPED_FILES letter(-s)."
    elif [[ "$CORRECT_FILES" -eq "0" && "$SKIPPED_FILES" -ge "1" ]]; then
      SUFFIX_NUMBER="0"
      while test -e "$MOUNTPATH/INBOX/$COUNTRY_ID$ZONE_ID$TERMINAL_ID$TERMINAL_UID$SUFFIX".TG; do
        ((++SUFFIX_NUMBER))
        SUFFIX="$(printf -- ' (%d)' "$SUFFIX_NUMBER")"
      done
      printf "Уважаемый пользователь!\r\n\r\nНам не удалось произвести отправку одного или нескольких сообщений, которые были расположены в директории OUTBOX.\r\n\r\nПожалуйста, убедитесь в том, что:\r\n\r\n  * Файл сообщения имеет расширение .TG\r\n  * Объём сообщения не превышает 65535 символов\r\n  * Указан правильный номер получателя письма\r\n  * Вы отправляете сообщение не самому себе\r\n\r\nОбратите внимание: все недоставленные письма всё ещё находятся в директории OUTBOX. Вы можете попытаться исправить ошибки и повторить отправку.\r\n\r\n--\r\nЭто сообщение было сгенерировано автоматически.\r\nПожалуйста, не отвечайте на него.\r\n" > "$MOUNTPATH/INBOX/$COUNTRY_ID$ZONE_ID$TERMINAL_ID$TERMINAL_UID$SUFFIX".TG

      # Notify user about skipped files count
      log info "Skipped $SKIPPED_FILES letter(-s), no correct letters were found."
    fi

  # If no outgoing mail were found
  else
    log notice "No outgoing mail were found. Skipping."
  fi

  # Check $TGPATH/MESSAGES/INGOING/$ID folder
  # for ingoing messages. Skip, if there is
  # no new ingoing messages are presented
  if [[ ! -z "$(ls -A $TGPATH/MESSAGES/INGOING/$ID 2>/dev/null)" ]]; then
    # Retrieve all new messages to $MOUNTPOINT/INBOX folder
    for FILE in "$TGPATH/MESSAGES/INGOING/$ID/"*.TG; do
      # +1 to retrieved messages count
      ((RETRIEVED_MESSAGES++))

      # Get file basename and remove extension
      FILE_BASENAME=$(basename "$FILE" | cut -f 1 -d '.')

      SUFFIX_NUMBER="0"
      while test -e "$MOUNTPATH/INBOX/$FILE_BASENAME$SUFFIX".TG; do
        ((++SUFFIX_NUMBER))
        SUFFIX="$(printf -- ' (%d)' "$SUFFIX_NUMBER")"
      done

      # Copy this file to $MOUNTPATH/INBOX
      cp "$FILE" "$MOUNTPATH/INBOX/$FILE_BASENAME$SUFFIX".TG

      # Remove this file from $TGPATH/MESSAGES/INGOING/$ID of user
      rm "$FILE"
    done
    
    # Notify user about retrieved messages
    log info "Retrieved $RETRIEVED_MESSAGES message(-s)."
      
  # If no ingoing mail were found
  else
    log notice "No ingoing mail were found. Skipping."
  fi

# If $DEVICE is not Telegraph device
# or not valid Telegraph device
else

  # 2. Prepare to format
  # 2.1. Force to create $MOUNTPATH
  # 2.2. Force to unmount $DEVICE
  # 2.3. Format $DEVICE to FAT32 with label "TELEGRAPH"
  # 2.4. Mount $DEVICE to $MOUNTPATH
  # 2.5. Fill $DEVICE with Telegraph data

  # Go!
  log notice "Setting up a $DEVICE..."; beep 1 &

  #
  # Prepare data for filling the Telegraph device
  #

  #
  # Device ID's stored in
  # $TGPATH/UUID/
  #
  # Hierarchy:
  #
  # $TGPATH/UUID/               - each file contents is equals to:
  #                              [TELEGRAPH]
  #                              ID=USER_ID
  #                              SECRET=SECRET_KEY (generated once)
  #                              - each file name is equals to DEVICE_HARDWARE_ID.TG
  #
  # $TGPATH/MESSAGES/INGOING/ID - each file contents is equals to:
  #                              MESSAGE_BODY
  #                              - each file name is equals to user ID,
  #                              what has been sended this file
  #                              - ID in path should be replaced by
  #                              recipient unique identification number
  #                              - each file extension is equals to .TG
  #
  # --------------------------------------------------------------------
  #    NEW USER ID's GENERATION
  # --------------------------------------------------------------------
  #
  # 1. Check $TGPATH/UUID/DEVICE_HARDWARE_ID.TG
  #    If device hardware ID exists and secret key is not equal
  #    for key, that stored in root partition of USB flash device,
  #    decline registration request and do not format the device
  #
  # 2. Generate new ID next to last ID, stored in this terminal,
  #    from 0001 up to 9999 per terminal
  #
  # 3. Create new file at $TGPATH/UUID/DEVICE_HARDWARE_ID.TG, filled with
  #    these data:
  #
  #    [TELEGRAPH]
  #    ID=USER_ID
  #    SECRET=SECRET_KEY
  #
  # 4. Finish the registration process
  #

  # Force to create subdirectories
  # in $TGPATH
  mkdir -p "$TGPATH/UUID"
  mkdir -p "$TGPATH/MESSAGES/"{INGOING,OUTGOING}

  # Check is this device already been registered
  if [[ -f "$TGPATH/UUID/$DEVICE_UUID.TG" ]]; then
    # Force to unmount $DEVICE
    umount -f "$DEVICE" &> /dev/null

    # Notify user that device is already been registered
    log error "Device is already been registered. Giving up!"; beep 8 &
    exit 1
  fi

  # Force to create $MOUNTPATH
  mkdir "$MOUNTPATH" &> /dev/null

  # Force to unmount $DEVICE
  umount -f "$DEVICE" &> /dev/null

  # Format $DEVICE to FAT32 with label "TELEGRAPH"
  mkdosfs -F 32 -i "`echo $DEVICE_UUID | sed 's/-//'`" -I "$DEVICE" -n "TELEGRAPH" &> /dev/null

  # Mount $DEVICE to $MOUNTPATH
  mount "$DEVICE" "$MOUNTPATH" &> /dev/null

  #
  # Register the device
  #

  # Generate new secret for ID
  NEW_ID_SECRET="`tr -cd '[:alnum:]' < /dev/urandom | fold -w64 | head -n1`"

  # Check is there is no devices
  # even been registered on this terminal
  if [[ -z "$(ls -A $TGPATH/UUID)" ]]; then
    NEW_ID="0001"
    printf "[TELEGRAPH]\nID=$COUNTRY_ID$ZONE_ID$TERMINAL_ID$NEW_ID\nSECRET=$NEW_ID_SECRET" > "$TGPATH/UUID/$DEVICE_UUID".TG
  else
    # Get second line of last modified file $TGPATH/UUID/$DEVICE_UUID.TG
    LAST_FILE_MODIFIED="`ls -Art $TGPATH/UUID      | tail -n 1`"
    LAST_ID="`cat $TGPATH/UUID/$LAST_FILE_MODIFIED | sed -n 2p | cut -d: -f1 | tail -c 5`"
    if [[ "$LAST_ID" != "9999" ]]; then
      LAST_ID="`echo $LAST_ID | sed 's/^0*//'`"; ((LAST_ID++))
      NEW_ID="`printf \"%04.f\" \"$LAST_ID\"`"
      printf "[TELEGRAPH]\nID=$COUNTRY_ID$ZONE_ID$TERMINAL_ID$NEW_ID\nSECRET=$NEW_ID_SECRET" > "$TGPATH/UUID/$DEVICE_UUID".TG
    else
      # Create README.TG file on device
      printf "Уважаемый пользователь!\r\n\r\nК сожалению, на этом терминале не осталось свободных номеров для регистрации." > "$MOUNTPATH/README".TG

      # Force to unmount $DEVICE
      umount -f "$DEVICE" &> /dev/null

      # Notify user that there is no ID's available on this terminal
      log error "No ID's available for registration on this terminal. Giving up!"; beep 8 &
      exit 1
    fi
  fi

  ID="$COUNTRY_ID$ZONE_ID$TERMINAL_ID$NEW_ID"
  SECRET="$NEW_ID_SECRET"

  # Set device type flag
  if [[ "$DEVICE_UUID" != "FFFF-FFFF" ]]; then
    # Common device type
    DEVICE_TYPE="COMMON"

    # Notify user about we are filling the common device
    log notice "Filling the common device..."
  else
    # POSTMAN device type
    DEVICE_TYPE="POSTMAN"

    # Notify user about we are filling the POSTMAN device
    log notice "Filling the POSTMAN device..."
  fi

  # Create this path only f this device is a common device,
  # because of POSTMAN device doesn't have INBOX and OUTBOX directories
  if [[ "$DEVICE_TYPE" == "COMMON" ]]; then
    # Create $TGPATH/MESSAGES/INGOING/$ID for new ID
    mkdir -p "$TGPATH/MESSAGES/INGOING/$ID"
  fi

  #
  # Fill $DEVICE with Telegraph data
  #

  # If this device is a common device
  if [[ "$DEVICE_TYPE" == "COMMON" ]]; then
    # Create INBOX and OUTBOX directories
    mkdir "$MOUNTPATH"/{INBOX,OUTBOX}
  # If this device is a POSTMAN device
  else
    # Create POSTMAN directory
    mkdir "$MOUNTPATH/POSTMAN"
  fi

  # Create SYSTEM.TG file with ID and SECRET
  printf "[TELEGRAPH]\r\nID=$ID\r\nSECRET=$SECRET" > "$MOUNTPATH/SYSTEM".TG

  # Make SYSTEM.TG file readonly and hidden
  fatattr +rh "$MOUNTPATH/SYSTEM".TG

  # Only if this device is a common device,
  # because of POSTMAN doesn't have INBOX and OUTBOX directories
  if [[ "$DEVICE_TYPE" == "COMMON" ]]; then
    # Send a letter by terminal to user
    printf "Уважаемый пользователь!\r\n\r\nВам присвоен новый уникальный идентификатор — $ID.\r\n\r\nБудьте внимательны: за каждым устройством закрепляется только один уникальный идентификатор. Вы не сможете использовать этот идентифиактор для обмена сообщениями, если устройство будет утрачено или его содержимое будет повреждено.\r\n\r\n--\r\nЭто сообщение было сгенерировано автоматически.\r\nПожалуйста, не отвечайте на него.\r\n" > "$MOUNTPATH/INBOX/$COUNTRY_ID$ZONE_ID$TERMINAL_ID$TERMINAL_UID".TG
  fi
fi

# Notify user that we are reached end of mail processing
log notice "Done!"; beep 2 &

# Unmount $DEVICE
umount "$DEVICE" &> /dev/null

# If $DEVICE can't me unmounted
if ! [[ "$?" -eq 0 ]]; then
  log error "Failed to unmount $DEVICE. Giving up!"; beep 8 &
  exit 1
fi