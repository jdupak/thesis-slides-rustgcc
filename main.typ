#import "@preview/polylux:0.3.1": *
#import "@preview/fletcher:0.3.0" as fletcher: node, edge
#import "theme/ctu.typ": *

#show: ctu-theme.with()

#title-slide[
    = Memory Safety Analysis for Rust GCC
    
    #v(0.75em)

    #set text(size: 1em)
    
    Jakub Dupák

    #v(1em)

    #set text(size: 0.7em)

    #table(
      columns: (1fr, 1fr),
      column-gutter: 0.5em,
      stroke: none,
      align: (right, left),
      [Supervisor:], [Ing. Pavel Píša PhD.],
      [Project reviewer:], [MSc. Arthur Cohen]
    )

    #v(1em)
    
    Faculty of Electrical Engineering \
    Department of Measurement

    #notes(
      ```md
      Vážená komise, dámy a pánové,
      dovolte abych vám představil výsledky své diplomové práce nazvané "Analýza bezpečného přístupu k paměti pro kompilátor Rust GCC".

      Cílem mé práce bylo implementovat statickou analýzu, známou jako "borrow checker" do vznikajícího nového překladače jazyka Rust nad platformou GCC.

      ~Rust je moderní jazyk pro systémové programování, který cílí primárně na oblasti dosud dominované jazyky C a C plus plus.
      Jeho hlavní předností je robustní typový systém, který mimo jiné poskytuje silné garance bezpečnosti přístupu do paměti a to i pro konkurentní kód. V poslední době můžeme vidět roustoucí adopci od Linuxováho a Windowsového kernelu a systémových knihoven,
      serverové systémy Amazonu, Dropboxu, Claudflare až po některé embedded zařízení.~
      ```
    )
]

#slide[
  = Outline

  - Borrow Checking Introduction
  - Polonius
  // - Rust GCC
  - Implementation
  - Results
  - Limitations
  - Polonius WG Review

  #notes(
    ```md
    - Nejprve vám krátce představím samotnou analýzu a její nejmodernější variantu, projekt Polonius, na kterém je založena tato práce.
    - Potom vás seznámím se základními aspekty implementační části této práce, dosaženými výsledky a aktuálními omezeními.
    - Svoji prezentaci zakončním zpětnou vazbou od vývojářů oficiálního překladače Rustu a projektu Polonius.
    ```
  )
]

#slide[
  = Borrow Checker Rules

  - Move
  #only(2)[
    ```rust
      let mut v1 = Vec::new();
      v1.push(42)
      let mut v2 = v1; // <- Move
      println!(v1[0]); // <- Error
    
    ```
    #v(0.5em)
  ]
  - Lifetime subset relation
  - Borrow must outlive borrowee
    #only(3)[
     ```rust
      fn f() -> &i32 {
        &(1+1)
      } // <- Error
     ```
    #v(0.5em)
  ]
  - One mutable borrow or multiple immutable borrows
  - No modification of immutable borrow data
    #only(4)[
      ```rust
        let mut counter = 0;
        let ref1 = &mut counter;
        // ...
        let ref2 = &mut counter; //  <- Error
      ```
    ]

  #notes(
    ```md
    Základní operací při práci s pamětí je přesun unikátních zdrojů do jiného objektu, takzvaný "move".
    
    Typickým příkladem je přiřazení vektoru (dynamického pole) do jiné proměné. V takovém případě musíme zajistit, že k přesunu unikátního objektu dojde pouze jednou a že k objektu není dále přistupováno z proměné, ze které byl přesunut.

    Pro dočasné používání objektu musíme zajistit, že objekt bude existovat po celou dobu dočasného používání. Typickou chybou v této oblasti je například návrat reference na lokální hodnotu.

    Pro bezpečnou součinost více vláken musíme zajistit buďto sdílený přístup více vláken pouze pro čtení, a nebo exkluzivní přístup pro zápis.
    ```
  )
]

#slide[
  = Lexical Borrow Checker

  #only(1)[
    ```rust
    {
      let mut data = vec!['a', 'b', 'c'];
      let slice = &mut data[..];
      capitalize(slice);         
      data.push('d'); 
      data.push('e');
      data.push('f');
    }
    ```
  ]
  #only(2)[
    ```rust
    {
      let mut data = vec!['a', 'b', 'c'];
      let slice = &mut data[..]; // <---+ 'lifetime
      capitalize(slice);         //     |
      data.push('d'); // ERROR!  //     |
      data.push('e'); // ERROR!  //     |
      data.push('f'); // ERROR!  //     |
    } // <------------------------------+
    ```

  ]


  #notes(
    ```md
    Hlavním problémem v této analýze je zjistit, jak dlouho bude bude dočasné používání objektu trvat.

    Dřívější verze borrow checker k tomu používaly lexikální analýzu. Zjednodušeně řečeno, dívaly se, na kterých řádcích musí být reference validní a to po podle scopu příslušných proměných.

    Tento příklad je neprávem hlášen jako chyba, protože metoda push vyžaduje vlastni referenci na vektor data.
    ```
  )
]

#slide[
  = Checking Functions

  ```rust
  struct Vec<'a> { ... }

  impl<'a> Vec<'a> {
    fn add<'b> where 'b: 'a (&mut self, x: &'b i32) {
      // ...
    }
  }
  ```

    #notes(
    ```md
    Protože analýza celého programu by měla extrémní výpočetní nároky, provádí borrow checker pouze analýzu uvnitř funkce.

    Na hranicích funkce musí programátor popsat popsat invarianty platnosti referencí a to pomocí lifetime anotací, na slidu apostrof a písmena `a` a `b`.

    Na příkladu zde máme vektor referencí, jejihž platnost v rámci programu je zdola omezena regionem apostrof `a`. Pokud chceme vložit fo vektoru novou referenci s platností apostrof `b`, musíme říci, že oblast programu apostrof `b` je alespoň tak velká, jako apostrof `a`.
    ```
  )
]

#slide[
  = NLL & Polonius

  #grid(columns: (3fr, 1fr))[
    ```rust
      fn f<'a>(map: Map<K, V>) -> &'a V {
        match map.get_mut(&key) {
          Some(value) => value,
          None => { 
            map.insert(key, V::default()); 
          }
        }
      }
    ```
  ][
    #set text(size: 0.75em, font: "Roboto Mono")

    #only(2)[
    #fletcher.diagram(
      {
      let (start, match, s, n, end, ret) = ((0,0), (0,-1), (-0.5, -2), (0.5, -2), (0, -3), (0, -4))
      node(start, "Start")
      node(match, "Match")
      node(s, "Some")
      node(n, "None")
      node(end, "End")
      node(ret, "Return")
      edge(start, match, "->")
      edge(match, s, "->")
      edge(match, n, "->")
      edge(s, end, "->")
      edge(n, end, "->")
      edge(end, ret, "->")
    })]
    #only(3)[
    #fletcher.diagram(
      {
      let (start, match, s, n, end, ret) = ((0,0), (0,-1), (-0.5, -2), (0.5, -2), (0, -3), (0, -4))
      node(start, "Start")
      node(match, "Match")
      node(s, "Some")
      node(n, text(fill:red, "None"))
      node(end, "End")
      node(ret, "Return")
      edge(start, match, "->")
      edge(match, s, "->")
      edge(match, n, "-->")
      edge(s, end, "->")
      edge(n, end, "->")
      edge(end, ret, "->")
    })]
  ]

    #notes(
      ```md
        Další verze borrow checkeru nazvaná "Non-lexical Lifetimes" provádí analýzu na control flow grafu, čímž značně omezuje false positive případy.

        Nicméně kód na slidu stále nedokáže validovat.
      ```
  )
]

// #slide[
//   = Rust Compilers

//   - *rustc*
//     - LLVM
//     - rustc_codegen_gcc
//     - Cranelift (Webassembly)
//   - *Rust GCC (gccrs)*
// ]

// #slide[
//   = Rust GCC

//    - rustc_codegen_gcc
//     - older
//     - crosscompilation
//     - LTO
//   - LLVM
//     - target support
//     - LTO
//     - optimizations
//     - security plugins
// ]

#slide[
  = Implementation

  - Parsing, AST, HIR
  - Lifetime handling in the type checker
  - Variance analysis
  - BIR construction
  - Fact collection
  - Polonius FFI
  - Error reporting
  - Changed #text(fill:green)[+10174] #h(10pt) #text(fill:red)[-1374]

  #notes(
    ```md
      Nyní se podíváme na jednotlivé části, které jsem implementoval, abych základní variantu analýzy, kterou jsem vám představil integroval do překladače Rust GCC.

      V první řadě bylo třeba zajistit správné parsování lifetime anotací a jejich reprezentaci v abstraktním syntaktickém stromě a vysoko-úrovňové reprezentaci.

      V dalším kroku bylo nutné provést resoluci jmen jednotlivých anotací, přiřazení použití k definicím a reprezentace unitř typového systému. Jednou z výsnamných komplikací bylo zajistit zachování správosti během operací na typech, a to hlavně během substituce generických typů.

      U generických typů bylo dále nutné spočítat takzvanou varianci generických argumentů. Variance určuje vztah mezi relacemi typů a relacemi generických parametrů těchto typů.

      Dalším krokem byl návrh zcela nové vnitří reprezentace, nazvané Borrow-checker IR. Jak jste viděli během představení analýzy, výpočet probíha na control flow grafu, kterým Rust GCC nedisponoval. Control flow graf programu je standartně vytvořem až hluboho uvnitř sdílené části platformy GCC a neobsahuje důležité informace specifické pro Rust.

      Z této nové reprezentace jsou pak získány relevatní informace o programu, které jsou očíslovány. Například: na uzlu control flow grafu číslo 5 došlo ke vniku exkluzivní reference číslo 8, která referuje na proměnou číslo 12.

      Tyto informace jsou následně předány výpočetnímu systému Polonius k samotné analýze. To, že komunikace s Poloniem probíhá pomocí těchnto očíslovaných informací nám umožnňuje Polonia využívat, i když byl původně vytvořen pro zcela jiný překladač.

      Protože je Polonius implementovaný v Rust, bylo nutné implementovat tenkou vrstvi C ABI a Rustu pro propojení s překladačem. Pomocí této vrstvy jsou zpět také předýny informace o nalezených chybách, které jsou překladačem předánu uživateli.
    ```
  )
]

#slide[
  = Results

  - Move errors
  - Subset errors
  - Access rule errors

    #notes(
    ```md
    A nyní už v výsledkům. Jak jste viděli, tak tato analýza vyžaduje úpravy ve velké části překladače. Tedy bylo nutné vybudovat rozsáhlou infrastrukturu, aby bylo možné vůbec začít se samotnou analýzou. Proto jsou možnosti implementované analýzi zatím omezené, na poměrně jednoduchý kód. Nicméně na tomto kódu dokážeme detekovat velkou část porušení pravidel přístupu k paměti.
    ```
  )
]

#let error(body) = {
  v(1em)
  text(font: "Roboto Mono", size: .8em)[
    *#text(fill:red)[Error:]* #body
  ]
}

#slide[
  == Borrow Rules
  ```rust
   fn mutable_borrow_while_immutable_borrowed() {
       let x = 0;
       let y = &x;     // <---
       let z = &mut x; // <---
       let w = y;
   }
   ```

   #uncover(2)[
     #error([Found loan errors in function
            mutable_borrow_while_immutable_borrowed])
  ]

    #notes(
      ```md
        Na tomto příkladu vydíte porušení pravidel o existenci více referencí.
      ```
    )
]

#slide[
  == Struct & Method
  
  ```rust
  struct Reference<'a> {
      value: &'a i32,
  }
  
  impl<'a> Reference<'a> {
      fn new<'a>(value: &'a i32) -> Reference<'a> {
          Reference { value: value }
      }
  }
  ```

    #notes(
      ```md
        Nicméně reálný kód často obsahuje reference uvnitř složitějších struktur. Pro demonstraci použijeme tuto strukturu obsahující referenci a konstruktor.
      ```
    )
]
  
#slide[
  == Borrow Rules with Struct
  ```rust
  fn mutable_borrow_while_immutable_borrowed_struct() {
      let x = 0;
      let y = Reference::new(&x);
      let z = &mut x; //~ ERROR
      let w = y;
   }
   ```

   #uncover(2)[
     #error([Found loan errors in function
            mutable_borrow_while_immutable_borrowed])
  ]

      #notes(
      ```md
        Zde můžete vidět, že analýza stále funguje i pokud je reference skrytá uvnitř struktury.
      ```
    )
]

#slide[
  == Subset Rules
  
  ```rust
  fn complex_cfg_subset<'a, 'b>(b: bool, x: &'a u32, y: &'b u32) -> &'a u32 {
      if b {
          y //~ ERROR
      } else {
          x
      }
  }
  ```

  #uncover(2)[#error([Found subset errors in function complex_cfg_subset])]

    #notes(
    ```md
      Zde je demostrována kontrola na hracinici funkce. V první větvi podmínky je navrácena reference, jejíž oblast života není jakkoliv provázána s návratovou hodnotou. Proto není možné prokázat, že vrácená reference vždy ukazuje na validní objekt.
    ```
  )
]

#slide[
  = Limitations
  
  - BIR builder
  - Error location and reason
  - Metadata export
  - Implicit constraints
  - Polonius build

      #notes(
      ```md
        Jak jsem zmínil, tato analýza je velmi komprexní problém a proto jsou možnosti moji implemetace limitované. Nicméně všechny známe limitace, popsané detailněji v textu mé práce, jsou technického charakteru a mělo by být možné je vyřešit prostým rozšířením existujícího kódu.

        Hlavní limitací je konstrukce nové mezi-reprezentace pro komplexní konstrukty jazyka Rust. Aktuálně je pokryta pouze základní část jazyka, který byla dostatečná pro testování zbytku analýzy.

        V tuto chvíli jsou informace pro chybová zprávy omezené na název funkce a typ chyby. Do budoucna je nutné přidat mapování na zdrojový kód.

        Analýza v tuto chvíli bere v potaz je jednu jednotku překladu. Je potřeba doplnit exporat a import informací o varianci pro používání knihoven.

        Protože Rust GCC není schopen v tuto chvíli sestavit Polonius, není možné integrovat ho do build systému GCC přímo.
      ```
    )
]

#slide[
  = Polonius WG Review
]

#title-slide[
  #image("image.png", height: 35%)
  #text(size: 2em)[Thank You] \
  #text(size:1.5em)[for your attention]
]