# DW1 Wild Digimon Randomizer

The wild Digimon roaming the File Island maps become **other Digimon of the same stage that share at least two of their specialties**. A Dokunemon (Earth and Air) in Native Forest can turn into a Muchomon or a Kunemon, an IceDevimon in Freezeland into a Devimon, Garurumon or Rockmon, a Tekkamon in the Back Dimension into a Giromon, SkullGreymon or Machinedramon.

- **Same stage**: Rookies stay Rookies, Champions stay Champions, Ultimates stay Ultimates.
- **Shared specialties**: at least two in common. A wild Digimon with only one specialty (Goburimon is Battle only) is replaced by Digimon that have it too.
- **Random techniques**: each wild Digimon fights with techniques drawn at random from all of its own, and its own finisher where the original had one. Two Greymon in one area can fight differently, and a wild Digimon that stays itself gets new techniques too. It has as many techniques as the original had.
- **Same difficulty**: HP, MP, stats and the bits you win stay those of the area, so the game's balance doesn't change.
- **Only wild Digimon**: story Digimon, bosses, recruits (such as the Coelamon at the Beach) and the Digimon in File City stay as they are.
- **The Arena too**: the opponents in File City's Arena tournaments are picked the same way, and each cup's rules hold: a replacement comes from that cup's own line-up and keeps the stage of the Digimon it replaces, so a Rookie Cup stays Rookies and a Fire Cup or Mech Cup keeps its fire or machine Digimon. Opponents no longer have to be Digimon you recruited, and none is your partner's own Digimon. The usual stats, prizes and medals apply.

**Options**

- **New Digimon**
  - **Every visit** (default): an area's wild Digimon are picked again each time you enter it.
  - **Fixed**: an area always has the same wild Digimon in one playthrough. Each save keeps its own: a New Game gets new ones, and loading a save brings back that save's. Saves made with 0.5.0 or older keep the Digimon they had.
- **Techniques**
  - **Random** (default): techniques drawn at random from all of the Digimon's own.
  - **Matched**: a replacement keeps a technique the original also knew, otherwise it uses one of its own of the same kind; a wild Digimon that stays itself keeps its techniques.
- **Arena opponents** (default on): randomize the Arena's tournament opponents too (see above). With **Every visit** each tournament draws new ones; with **Fixed** a cup always turns the same Digimon into the same replacement.
- **Include Expanded Roster Digimon** (default on): with DW1 Expanded Roster installed, its new Digimon can be picked too (see below).

**Notes**

- Each wild Digimon is picked on its own, so three Dokunemon in Native Forest can become a Muchomon and two Kunemon. The game loads one model per kind of Digimon in an area and has room for five, so a second or third replacement for the same kind is only picked while its model still fits; otherwise it is one of that kind's replacements again.
- A technique is only picked when the Digimon's model has its animation, so Digimon whose model was made for a few moves (Gotsumon, Tankmon, Tekkamon, the story Digimon's copies) have little to choose from.
- **More memory for the Digimon on a map.** On a PlayStation the game keeps every Digimon model of a map in about 190 KB, so bigger replacements used to turn up less often in crowded areas. The mod now gives the console the 8 MB of memory Sony's development consoles had and moves that space into the extra 6 MB, so a replacement's model always fits, whatever its size. The game itself runs as before. ClearAgumon still stays itself: no other Rookie shares its specialties.
- The game still loads at most five kinds of Digimon models on a map, so an area with many kinds of wild Digimon gives some of them the same replacement.
- A replacement loads a lighter copy of its model, made when the game starts, with only what a wild Digimon uses (Greymon, Angemon or Patamon leave out their care, training and menu motions), so a map loads faster.
- **Save states** made with 0.5.0 or older don't load with this version (the console has more memory now); your memory card saves are not affected.
- Some of the game's Digimon exist only as cut-down copies made for one story scene (Kuwagamon's, Elecmon's, Leomon's and others). Those copies can't walk and fight like wild Digimon, so the mod uses the full versions of those Digimon instead, when they fit.
- **DW1 Expanded Roster** (USA only, like that mod): the two mods work together in either order. The randomizer reads the Digimon tables where Expanded Roster moves them, and its new Digimon are part of the pool: a Guilmon pack in Toy Mansion, Renamon in Freezeland, Growlmon in Toy Town. On a map, Expanded Roster loads a lighter copy of each one, with all of its techniques from 0.20.0 on (its finisher and three others before). With Expanded Roster 0.11.0 or older, which has no such copies, they are counted at the largest size a Digimon's model can have. Where Digimon World has its own model of a Digimon (Gotsumon, Goburimon, Tankmon...), the randomizer uses that one. In the Arena, Expanded Roster's new Digimon (0.21.0 or newer, which draws them in the bracket) can take an opponent's place in the grade cups (Grade D to Grade R), which are open to every Digimon of a stage; the version and theme cups keep their own line-ups.

Made for Digimon World (USA, SLUS-01032) and checked there, alone and with DW1 Expanded Roster: areas from Native Forest to the Back Dimension, battles against the replacements, Arena cups (Rookie, Champion, Ultimate, Fire, Ice, Air and Mech), and the game's check mode.

Also works on Digimon World (Europe, SLES-02914), whose executable has the same code built differently: the mod has its own list of addresses for each release. Checked on a new European game: Native Forest's ModokiBetamon became Betamon and its RedVegiemon Ogremon, Ninjamon or Kabuterimon, a battle against one of the Betamon played through, the lighter model copies loaded, and check mode found nothing amiss. The European Arena code was checked against the American one but no tournament was played there.

Needs Re:Compiled 1.10 or newer.
