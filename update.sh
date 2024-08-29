#!/bin/sh

declare -A replacements=(
    ["\.Type\b"]="\.type"
    ["\.Void\b"]="\.void"
    ["\.Bool\b"]="\.bool"
    ["\.NoReturn\b"]="\.noreturn"
    ["\.Int\b"]="\.int"
    ["\.Float\b"]="\.float"
    ["\.Pointer\b"]="\.pointer"
    ["\.Array\b"]="\.array"
    ["\.Struct\b"]="\.@\"struct\""
    ["\.ComptimeFloat\b"]="\.comptime_float"
    ["\.ComptimeInt\b"]="\.comptime_int"
    ["\.Undefined\b"]="\.undefined"
    ["\.Null\b"]="\.null"
    ["\.Optional\b"]="\.optional"
    ["\.ErrorUnion\b"]="\.error_union"
    ["\.ErrorSet\b"]="\.error_set"
    ["\.Enum\b"]="\.@\"enum\""
    ["\.Union\b"]="\.@\"union\""
    ["\.Fn\b"]="\.@\"fn\""
    ["\.Opaque\b"]="\.@\"opaque\""
    ["\.Frame\b"]="\.frame"
    ["\.AnyFrame\b"]="\.@\"anyframe\""
    ["\.Vector\b"]="\.vector"
    ["\.EnumLiteral\b"]="\.enum_literal"
    ["builtin\.type"]="builtin\.Type"
)

if [[ -z "$1" ]]; then
    echo "Usage: $0 /path/to/src/dir"
    exit 1
fi

if [[ ! -d "$1" ]]; then
    echo "$1 is not a director"
    exit 1
fi

for file in $(find "$1" -type f -name '*.zig'); do 
    if [[ -f "$file" ]]; then
        for key in "${!replacements[@]}"; do
            sed -i "s/$key/${replacements[$key]}/g" "$file"
        done
    else
        echo "$file is not a file, skipping..."
    fi
done
