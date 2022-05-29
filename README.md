# zerodisk

Copyright (C) 2021-2022 Kenneth Aaron.

flyingrhino AT orcon DOT net DOT nz

Freedom makes a better world: released under GNU GPLv3.

https://www.gnu.org/licenses/gpl-3.0.en.html

This software can be used by anyone at no cost, however, if you like using my software and can support - please donate money to a children's hospital of your choice.

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation: GNU GPLv3. You must include this entire text with your distribution.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
See the GNU General Public License for more details.


# Manual install instructions

* Copy:  **zerodisk.sh**   to : **/usr/local/bin/** .
* Requires:  [rhinolib](https://github.com/flyingrhinonz/rhinolib_bash)  to run.



# Usage

* Writes then deletes large files of zeros to your disks empty space to make images with:  `df` more compact.
Use: `zerodisk 3 3`  before doing a:  `df`  image and notice the smaller size image.

* Script takes 2 arguments:
    * arg1: Untouched free space in Mb (write zeros to partition size minus this value)
        * miniumum value == 2 Mb
    * arg2: Minimum free space in Mb per partition for zerodisk to run
        * miniumum value == 3 Mb

* Example:  `zerodisk 10 25`

* You can further control the script via these vars:
    * `InfoOnly=[true|false]` - show info only or actually write zeros.
    * `ExcludePaths=()` - array of paths to exclude from zeroing.


Enjoy...


