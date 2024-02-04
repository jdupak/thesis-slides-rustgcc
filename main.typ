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
      ```
    )
]

#slide[
  = Borrow Checker Rules

  #only("1-2")[
    - Move
  ]
  #only("3-")[#text(fill: luma(50%))[
    - Move
  ]]
  #only(2)[
    ```rust
      let mut v1 = Vec::new();
      v1.push(42)
      let mut v2 = v1; // <- Move
      println!(v1[0]); // <- Error
    
    ```
    #v(0.5em)
  ]
  #only("1-3")[
    - Lifetime subset relation
    - Borrow must outlive borrowee
  ]
  #only("4-")[#text(fill: luma(50%))[
    - Lifetime subset relation
    - Borrow must outlive borrowee
  ]]

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
    Nejdříve vám seznámím se samotnou analýzou a problémy které řeší.
    
    Základní operací při práci s pamětí je přesun unikátních zdrojů, takzvaný "move".
    
    Pro move musíme zajistit, že unikátní zdroj není duplikován a že k původnímu, nyní nevalidnímu objektu, není dále přistupováno.

    Pro dočasné používání, což je například volání metody, musíme zajistit, že objekt bude existovat po celou dobu tohoto používání. Typickou chybou v této oblasti je například návrat reference na lokální hodnotu.

    Pro bezpečnou součinost více vláken musíme zajistit buďto sdílený přístup pouze pro čtení, a nebo exkluzivní přístup pro zápis.
    ```
  )
]

#slide[
  = Checking Functions

  #let f = ```rust
  struct Vec<'a> { ... }

  impl<'a> Vec<'a> {
    fn push<'b> where 'b: 'a (&mut self, x: &'b i32) {
      // ...
    }
  }
  ```

  #only("1")[#f]
  #only("2-")[
    #text(size: 0.7em, f)

    ```rust
    let a = 5;                     //  'a   'b   'b: 'a
    {                              //              
       let mut v = Vec::new();     //   *          
       v.push(&a);                 //   *    *     OK
       let x = v[0];               //   *    *     OK
     }                             //        *     OK
    ```
  ]

    #notes(
    ```md
    Protože analýza celého programu by měla extrémní výpočetní nároky, provádí borrow checker pouze analýzu uvnitř funkce.

    Na hranicích funkce musí programátor popsat popsat invarianty platnosti referencí a to pomocí lifetime anotací, na slidu apostrof `a` a apostrof `b`.

    Na příkladu zde máme vektor referencí, jejihž platnost v rámci programu je zdola omezena regionem apostrof `a`. Pokud chceme vložit fo vektoru novou referenci s platností apostrof `b`, musíme říci, že oblast programu apostrof `b` je alespoň tak velká, jako apostrof `a`.

    Zde na konrétním příkladu, můžete vidět dosazené časti programu.
    ```
  )
]

#slide[
  = CFG Computation

  #grid(columns: (3fr, 1fr))[
    ```rust
      fn f<'a>(map: Map<K, V>) -> &'a V {
        // Lookup key in map.
        // Return reference to value.
        match map.get_mut(&key) {
          Some(value) => value, // Found one.
          None => {
            // Not found.
            // New reference to map!
            map.insert(key, V::default());
          }
        }
      }
    ```
  ][
    #set text(size: 0.75em, font: "Roboto Mono")

    #only(1)[
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
    #only(2)[
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
        Nejtěší částí analýzy je dosazení konrétních částí programu za lifetime proměné, tedy nalezení oblastí, kde musí být dané reference validní.

        Moderní borrow checker musí provádět výpočet na control flow grafu, jinak by velmi silně programátora omezoval.

        Povšimněte si zde na příkladu, že při vstupu do větve None není žádná reference do proměné map platná, protože metoda získávají tuto referenci selhala. Moderní borrow borrow checker musí vzít v potaz i takové situace.
      ```
  )
]

#slide[
  #only("1,4-")[
    = Implementation
  ]
  #only("1")[
    - Parsing, AST, HIR
    - Lifetime handling in the type checker
    - Variance analysis

      $A angle.l 'a, T angle.r lt.eq B angle.l 'b, F angle.r arrow.double ('a subset.eq 'b) and (T lt.eq F)$
  ]
  #only("4-")[#text(fill: luma(50%))[
    - Parsing, AST, HIR
    - Lifetime handling in the type checker
    - Variance analysis
    - BIR construction
  ]]
  #only("2")[
      #block(width: 100%, align(center, image("media/pipeline.svg", height: 80%)))
  ]
  #only("3")[
      #block(width: 100%, align(center, image("media/bir.svg", height: 80%)))
  ]
  #only("4")[
    - Fact collection
    - Polonius FFI
    - Error reporting
  ]
  #only("5-")[#text(fill: luma(50%))[
    - Fact collection
    - Polonius FFI
    - Error reporting
  ]]
  #only("5-")[
    - Changed #text(fill:green)[+10174] #h(10pt) #text(fill:red)[-1374]
      - _48%_ GCC upstream
      - _11%_ Rust GCC
      - _~~~9%_ PR in review
  ]

  #notes(
    ```md
      Nyní se podíváme na jednotlivé části, které jsem implementoval, abych základní variantu této analýzy integroval do překladače Rust GCC.

      V první řadě bylo třeba zajistit správné parsování lifetime anotací a jejich reprezentaci v abstraktním syntaktickém stromě a vysoko-úrovňové reprezentaci.

      V dalším kroku bylo nutné provést resoluci jmen jednotlivých anotací, přiřazení použití k definicím a reprezentace unitř typového systému.
      Jednou z významných komplikací bylo zajistit zachování správosti během operací na typech, a to hlavně během substituce typových parametrů.

      U generických typů bylo dále nutné spočítat takzvanou varianci generických argumentů. Variance určuje vztah mezi relacemi typů a relacemi generických parametrů těchto typů. Příklad na slidu.

      Dalším krokem byl návrh zcela nové vnitří reprezentace, nazvané Borrow-checker IR. Jak jste viděli během představení analýzy, výpočet probíha na control flow grafu.
      
      Na tomto srovnání vnitřních reprezentací Rust GCC and rustc můžete vidět, že zatím co abstraktní syntaktický strom a vysoko úrovňová reprezentace, která má také formu stromu je obou kompilátorům společná. Rust GCC předává middle-endu program ve formě stromu, zatímco rustc má vlastní reprezentaci MIR, založenou na control flow grafu. Právě na MIRu probíhá v rustc borrow checking.

      Control flow graf GCC není pro tyto účely dostatečný, protože neopsahuje informace specifické pro rust. Proto bylo nutné vytvořit novou reprezentaci inspirovanou MIRerm, a přeložit do ní program s vysokoúrovňové reprezentace a reprezetace typů.

      Z této nové reprezentace jsou pak získány relevatní informace o programu, předány výpočetnímu systému Polonius, vivinutému vývojáři rustc, k samotné analýze.

      Protože je Polonius implementovaný v Rust, bylo nutné implementovat FFI vrstvu pro propojení s překladačem.

      Moje řešení zahrnuje zhruba deset tisíc řídek kódu v různých částech projektu. Téměr polovina již byla přijata do hlavního repozitáře GCC. U dalších 20% probíhá review pull requestu a zbytek je prozatím v mé vývojové větvi.
    ```
  )
]
#slide[
  = Results


  - Limitations
  \
  - Move errors
  - Subset errors
  - Access rule errors

  
    #notes(
    ```md
    Jak jste viděli, tak tato analýza vyžaduje úpravy ve velké části překladače. Tedy bylo nutné vybudovat rozsáhlou infrastrukturu, aby bylo možné vůbec **začít** se samotnou analýzou. Proto jsou možnosti implementované analýzi zatím omezené na poměrně **jednoduchý kód**. Nicméně na tomto kódu dokážeme detekovat velkou část porušení pravidel přístupu k paměti.


    Známe limitace, jsou popsané detailněji v textu mé práce, a všechny jsou technického charakteru a mělo by být možné je vyřešit prostým rozšířením existujícího kódu.

    Hlavní limitací je překlad složitých jazykových kontruktů do nové reprezentace.
    ```
  )
]

#let error(body) = {
  v(1em)
  text(font: "DejaVu Sans Mono", size: .8em)[
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

     #error([Found loan errors in function
            mutable_borrow_while_immutable_borrowed])

    #notes(
      ```md
        Na tomto příkladu vydíte porušení pravidel o současné existenci více referencí.
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

     #error([Found loan errors in function
            mutable_borrow_while_immutable_borrowed])

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

  #error([Found subset errors in function complex_cfg_subset])
    #notes(
    ```md
      Zde je demostrována kontrola na hracinici funkce. V první větvi podmínky je navrácena reference, jejíž životnost není jakkoliv provázána s návratovou hodnotou. Proto není možné prokázat, že vrácená reference vždy ukazuje na validní objekt.
    ```
  )
]


#slide[
  = Future

  - Open Source Security support
  - GSoC 2024

    #notes(
      ```md
        Co se budoucnosti této práce týče, pokud to bude v rámci mé další kariéry možné, chtěl bych na projektu pokračovat.
        Můžu zmínit, že společnosti Open Source Security, jeden z hlavních sponzorů Rust GCC projevila zájem o financování pokračování mé práce.

        Dále také připravujeme projekt do Google Summer of Code, který by řešil některé z  limitací.
      ```
    )
]
#title-slide[
  #image("media/gccrs.png", height: 35%)
  #text(size: 2em)[Thank You] \
  #text(size:1.5em)[for your attention]
]