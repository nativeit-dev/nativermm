ment
    ;;
    
    # repo arg
    --repo)
        [[ -z "$MODE" ]] && echo >&2 "Missing install or update first argument. Exiting..."; exit 1;
        [[ "$MODE" != "install" ]] || [[ "$MODE" != "update" ]] && \
        echo >&2 "--repo option only valid for install and update. Exiting..."; exit 1;
        
        shift # past argument
        REPO="$key"
        shift # past value
    ;;
    
    # branch arg
    --branch)
        [[ -z "$MODE" ]] && echo >&2 "Missing install or update first argument. Exiting..."; exit 1;
        [[ "$MODE" != "install" ]] || [[ "$MODE" != "update" ]] && \
        echo >&2 "--branch option only valid for install and update. Exiting..."; exit 1;
        
        shift # past argument
        BRANCH="$key"
        shift # past value
    ;;
    
    # version arg
    --version)
        [[ -z "$MODE" ]] && echo >&2 "Missing install or update first argument. Exiting..."; exit 1;
        [[ "$MODE" != "install" ]] || [[ "$MODE" != "update" ]] && \
        echo ">&2 --version option only valid for install and update. Exiting..."; exit 1;
        
        shift # past argument
        VERSION="$key"
        shift # past value
    ;;
    
    # noninteractive arg
    --noninteractive)
        [[ -z "$MODE" ]] && echo >&2 "Missing install first argument. Exiting..."; exit 1;
        [[ "$MODE" != "install" ]] && echo >&2 "--noninteractive option only valid for install. Exiting..."; exit 1;
        NONINTERACTIVE=1
        
        shift # past argument
    ;;
    
    # app host arg
    --app-host)
        [[ -z "$MODE" ]] && echo >&2 "Missing install first argument. Exiting..."; exit 1;
        [[ "$MODE" != "install" ]] && echo >&2 "--app-host option only valid for install. Exiting..."; exit 1;
        
        shift # past argument
        APP_HOST="$key"
        shift # past value
    ;;
    
    # api host arg
    --api-host)
        [[ -z "$MODE" ]] && echo >&2 "Missing install first argument. Exiting..."; exit 1;
        [[ "$MODE" != "install" ]] && echo >&2 "--api-host option only valid for install. Exiting..."; exit 1;
        
        shift # past argument
        API_HOST="$key"
        shift # past value
    ;;
    
    # mesh host arg
    --mesh-host)
        [[ -z "$MODE" ]] && echo >&2 "Missing install first argument. Exiting..."; exit 1;
        [[ "$MODE" != "install" ]] && echo >&2 "--mesh-host option only valid for install. Exiting..."; exit 1;
        
        shift # past argument
        MESH_HOST="$key"
        shift # past value
    ;;
    
    # nativermm user arg
    --nativermm-user)
        [[ -z "$MODE" ]] && echo >&2 "Missing install first argument. Exiting..."; exit 1;
        [[ "$MODE" != "install" ]] && echo >&2 "--nativermm-user option only valid for install. Exiting..."; exit 1;
        
        shift # past argument
        USERNAME="$key"
        shift # past value
    ;;
    
    # nativermm password arg
    --nativermm-password)
        [[ -z "$MODE" ]] && echo >&2 "Missing install first argument. Exiting..."; exit 1;
        [[ "$MODE" != "install" ]] && echo >&2 "--nativermm-password option only valid for install. Exiting..."; exit 1;
        
        shift # past argument
        PASSWORD="$key"
        shift # past value
    ;;
    
    # email arg
    --email)
        [[ -z "$MODE" ]] && echo >&2 "Missing install first argument. Exiting..."; exit 1;
        [[ "$MODE" != "install" ]] && echo >&2 "--email option only valid for install. Exiting..."; exit 1;
        
        shift # past argument
        EMAIL="$key"
        shift # past value
    ;;
    
    # Unknown arg
    *)
        echo "Unknown argument ${$1}. Exiting..."
        exit 1
    ;;
esac
done


# for install mode
if [[ "$MODE" == "install" ]]; then
echo "Starting installation in ${INSTALL_DIR}"

# move to install dir
mkdir -p "${INSTALL_DIR}"
cd "$INSTALL_DIR"

# pull docker-compose.yml file
echo "Downloading docker-compose.yml from branch ${BRANCH}"
COMPOSE_FILE="https://raw.githubusercontent.com/${REPO}/nativermm/${BRANCH}/docker/docker-compose.yml"
if ! curl -sS "${COMPOSE_FILE}"; then
    echo >&2 "Failed to download installation package ${COMPOSE_FILE}"
    exit 1
fi

# check if install is noninteractive
if [[ -z "$NONINTERACTIVE" ]]; then
    # ask user for information not supplied as arguments
    ask_questions
    
else
    echo "NonInteractive mode set."
    # check for required noninteractive arguments
    [[ -z "$API_HOST" ]] || \
    [[ -z "$APP_HOST" ]] || \
    [[ -z "$MESH_HOST" ]] || \
    [[ -z "$EMAIL" ]] || \
    [[ -z "$USERNAME" ]] || \
    [[ -z "$PASSWORD" ]] && \
    echo "You must supply additional arguments for noninteractive install."; exit 1;
fi

# if certificates are available base64 encode them
if [[ -n "$LET_ENCRYPT" ]] && [[ -z "$NONINTERACTIVE" ]]; then
    initiate_letsencrypt
    encode_certificates
    elif [[ -n "$CERT_PUB_FILE" ]] && [[ -n "$CERT_PRIV_FILE" ]]; then
    encode_certificates
    
    # generate config file
    generate_config
    
    # generate env file
    generate_env
    
    echo "Configuration complete. Starting environment."
    # start environment
    docker-compose pull
    docker-compose up -d
    
fi

# for update mode
if [[ "$MODE" == "update" ]]; then
    [[ "$VERSION" != "latest" ]]
    docker-compose pull
    docker-compose up -d
fi

# for update cert mode
if [[ "$MODE" == "update-cert" ]]; then
    # check for required parameters
    [[ -z "$LET_ENCRYPT" ]] || \
    [[ -z "$CERT_PUB_FILE" ]] && \
    [[ -z "$CERT_PRIV_FILE" ]] && \
    echo >&2 "Provide the --lets-encrypt option or use --cert-pub-file and --cert-priv-file. Exiting..."; exit;
    
    if [[ -n "$LET_ENCRYPT" ]]; then
        initiate_letsencrypt
        encode_certificates
        generate_env
        elif [[ -n "$CERT_PUB_FILE" ]] && [[ -n "$CERT_PRIV_FILE" ]]; then
        encode_certificates
        generate_env
        
        docker-compose restart
    fi
    
    # for backup mode
    if [[ "$MODE" == "backup" ]]; then
        echo "backup not yet implemented"
    fi
    
    # for restore mode
    if [[ "$MODE" == "restore" ]] then;
        echo "restore not yet implemented"
    fi
    